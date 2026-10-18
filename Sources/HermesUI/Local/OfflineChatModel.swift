#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The offline side of one server chat (WP-65b, plan Q44).
    ///
    /// While the server is out of reach, new messages go to the on-device model. They are kept here, in an offline chat
    /// of their own: nothing is written to the server session. When the server is back, ``offer`` proposes to send the
    /// last prompt to Hermes. The model follows the connection's phase, so there is no extra network probe.
    @MainActor
    @Observable
    public final class OfflineChatModel {
        /// What the banner says.
        public enum Notice: Equatable, Sendable {
            /// "Offline, no Hermes tools": messages go to the on-device model.
            case offline
            /// The server is out of reach and the on-device model cannot answer.
            case unavailable(LocalModelUnavailable)
        }

        /// The offline chat as the screen shows it.
        public private(set) var snapshot = OfflineChatSnapshot()
        /// Where a new message goes now.
        public private(set) var route = OfflineRoute.server
        /// How far the server can be reached.
        public private(set) var reachability = ServerReachability.unknown

        /// The messages of the offline chat, oldest first.
        public var messages: [OfflineChatMessage] { snapshot.messages }

        /// The banner to show, or nil while messages go to the server.
        public var notice: Notice? {
            switch route {
            case .server: nil
            case .offline: .offline
            case .unavailable(let reason): .unavailable(reason)
            }
        }

        /// The "Send to Hermes" offer: the last prompt written offline, once the server is reachable again.
        public var offer: SendToHermesOffer? {
            SendToHermes.offer(chat: snapshot.chat, messages: snapshot.messages, server: reachability)
        }

        /// Where "Get a better model" goes, when the app has such a screen (WP-65c).
        public var getBetterModel: (@MainActor () -> Void)? { services?.onGetBetterModel }

        @ObservationIgnored private let services: OfflineChatServices?
        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let storedSessionID: String
        @ObservationIgnored private let clock: any GatewayClock
        @ObservationIgnored private var router = OfflineRouter()
        @ObservationIgnored private var controller: OfflineChatController?
        @ObservationIgnored private var tasks: [Task<Void, Never>] = []
        @ObservationIgnored private var wake: Task<Void, Never>?

        init(
            services: OfflineChatServices?, connections: ConnectionsModel, storedSessionID: String,
            clock: any GatewayClock = SystemGatewayClock()
        ) {
            self.services = services
            self.connections = connections
            self.storedSessionID = storedSessionID
            self.clock = clock
        }

        /// Opens the offline chat of this server chat and starts following the connection. Safe to call again.
        func start() {
            guard tasks.isEmpty, let services, let manager = connections.manager, let id = connections.active?.id else {
                return
            }
            let sessionID = storedSessionID
            tasks = [
                Task { [weak self] in
                    let controller = await OfflineChatController(
                        store: services.store, executor: services.executor, connection: id.uuidString,
                        sessionID: sessionID)
                    guard !Task.isCancelled else { return }
                    self?.controller = controller
                    for await next in await controller.states() {
                        self?.snapshot = next
                    }
                },
                Task { [weak self] in
                    let changes = await manager.phaseChanges()
                    let current = await manager.phase(of: id)
                    self?.observe(current)
                    for await change in changes where change.id == id {
                        self?.observe(change.phase)
                    }
                },
            ]
        }

        /// Stops following.
        func stop() {
            for task in tasks { task.cancel() }
            tasks = []
            wake?.cancel()
            wake = nil
            controller = nil
        }

        /// Takes a message when the route is offline: the on-device model answers it. Returns false when the message
        /// belongs to the server, so the caller sends it there as usual.
        func send(_ text: String) -> Bool {
            refreshRoute()
            guard route == .offline, let controller else { return false }
            HermesSounds.play(.send)
            Task { await controller.send(text) }
            return true
        }

        /// Works out the route again after something other than the connection changed it, such as the Settings switch.
        func refresh() {
            refreshRoute()
        }

        /// Closes the offline chat after the user answered the "Send to Hermes" offer.
        func resolveOffer(_ resolution: OfflineChat.Resolution) {
            guard let controller else { return }
            Task { await controller.resolve(resolution) }
        }

        // MARK: - Route

        private func observe(_ phase: ConnectionPhase) {
            reachability = ServerReachability(phase)
            router.observe(phase, at: clock.now())
            refreshRoute()
        }

        /// Works out the route again, and wakes up when the grace period ends if an outage is under way.
        private func refreshRoute() {
            guard let services else { return }
            let now = clock.now()
            route = router.route(
                onDeviceEnabled: services.settings.isEnabled, availability: services.executor().availability, at: now)
            wake?.cancel()
            wake = nil
            guard let deadline = router.offlineAt, deadline > now else { return }
            let clock = clock
            wake = Task { [weak self] in
                try? await clock.sleep(seconds: deadline - now)
                guard !Task.isCancelled else { return }
                self?.refreshRoute()
            }
        }
    }

    extension OfflineChatModel {
        /// A model with fixed state, for previews and snapshots. It follows no connection.
        static func preview(
            snapshot: OfflineChatSnapshot = OfflineChatSnapshot(), route: OfflineRoute = .server,
            reachability: ServerReachability = .unknown
        ) -> OfflineChatModel {
            let model = OfflineChatModel(services: nil, connections: .preview([]), storedSessionID: "preview")
            model.snapshot = snapshot
            model.route = route
            model.reachability = reachability
            return model
        }
    }
#endif
