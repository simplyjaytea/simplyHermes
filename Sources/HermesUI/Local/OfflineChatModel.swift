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

        /// True while the offer on screen is on its way to Hermes. Its buttons stay off, so a second tap cannot send
        /// the prompt twice.
        public var isSendingOffer: Bool { sending.isSending(offer) }

        /// Where "Get a better model" goes, when the app has such a screen (WP-65c).
        public var getBetterModel: (@MainActor () -> Void)? { services?.onGetBetterModel }

        private var sending = SendToHermesProgress()
        @ObservationIgnored private let services: OfflineChatServices?
        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let storedSessionID: String
        @ObservationIgnored private let clock: any GatewayClock
        @ObservationIgnored private var router = OfflineRouter()
        @ObservationIgnored private var controller: OfflineChatController?
        /// The saved connection's id, as the controller keys it. It outlives ``stop()``, so a chat can still be closed.
        @ObservationIgnored private var connectionKey: String?
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
            connectionKey = id.uuidString
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

        /// Marks `offer` as on its way to Hermes. Returns false when it already is, so only the first tap sends.
        func beginSending(_ offer: SendToHermesOffer) -> Bool {
            sending.begin(offer)
        }

        /// The send did not go through, so the offer can be tapped again.
        func sendFailed() {
            sending.fail()
        }

        /// Closes the offline chat after the user answered the "Send to Hermes" offer. A model that was stopped has no
        /// controller left, so the chat is closed in the store instead: an offer that was answered must not come back.
        func resolveOffer(_ offer: SendToHermesOffer, as resolution: OfflineChat.Resolution) {
            if let controller {
                Task { await controller.resolve(resolution) }
            } else if let store = services?.store, let connectionKey {
                let chatID = offer.chatID
                Task { try? await store.resolve(chat: chatID, connection: connectionKey, as: resolution, at: Date()) }
            }
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
