#if canImport(UIKit)
    import HermesKit
    import Observation

    /// Where the Gateway screen stands.
    public enum ServerControlPhase: Sendable, Equatable {
        case idle
        /// An action runs. Stop and restart show "Reconnecting…" while the server is away.
        case working(ServerControlAction)
        /// The last action's result, in words.
        case done(String)
        /// The last action failed, in words.
        case failed(String)
    }

    extension ServerControlStatus {
        /// Sample values for previews.
        static var sample: ServerControlStatus {
            ServerControlStatus(
                releaseDate: "2026.9.24", latestConfigVersion: 50, overall: "ok", gatewayRunning: true,
                gatewayState: "running", gatewayMode: "multiplex", gatewayBusy: false, gatewayDrainable: true,
                canUpdateHermes: true)
        }
    }

    /// The Gateway screen (Settings > Server > Gateway): the server's gateway status and start, stop, restart and
    /// drain. Each action asks first. Stop and restart wait up to 60 s for the server (WP-54).
    @MainActor
    @Observable
    public final class ServerControlModel {
        /// The last status read, kept on screen when a later read fails.
        public private(set) var status: ServerControlStatus?
        /// The idle diagnostic, as rows. Empty when the server did not answer it.
        public private(set) var idleRows: [ServerStatsRow] = []
        public private(set) var phase: ServerControlPhase = .idle
        public private(set) var isLoading = false
        /// Set when the status could not be read.
        public private(set) var errorText: String?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let clock: any GatewayClock

        public init(connections: ConnectionsModel, clock: any GatewayClock = SystemGatewayClock()) {
            self.connections = connections
            self.clock = clock
        }

        /// True while an action runs, so the buttons stay off.
        public var isBusy: Bool {
            if case .working = phase { return true }
            return false
        }

        /// Reads the status and the idle diagnostic of the active server.
        public func load() async {
            guard connections.manager != nil else { return }
            guard let connection = connections.active, let backend = serverControlBackend(connections, connection)
            else {
                errorText = "Choose a server in Settings > Servers."
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await backend.rest()
                status = try await rest.controlStatus()
                errorText = nil
                let idle = try? await rest.healthIdle()
                idleRows = idle.map { ServerStatsRows.rows(from: $0) } ?? []
            } catch {
                errorText = ServerControlError.describe(error)
            }
        }

        /// Sends one gateway action and records what came back. Then reads the status again.
        public func perform(_ action: ServerControlAction) async {
            guard !isBusy, let connection = connections.active,
                let backend = serverControlBackend(connections, connection)
            else { return }
            phase = .working(action)
            do {
                let outcome = try await backend.perform(action, clock: clock)
                phase = .done(Self.message(for: action, outcome))
            } catch {
                phase = .failed(ServerControlError.describe(error))
            }
            await load()
        }

        /// The button and dialog name for an action.
        public static func title(for action: ServerControlAction) -> String {
            switch action {
            case .start: return "Start gateway"
            case .stop: return "Stop gateway"
            case .restart: return "Restart gateway"
            case .drain: return "Drain gateway"
            case .cancelDrain: return "Cancel drain"
            }
        }

        /// The line shown after an action.
        static func message(for action: ServerControlAction, _ outcome: ServerControlActionOutcome) -> String {
            let name = title(for: action)
            switch outcome {
            case .sent: return "\(name) sent."
            case .reconnected: return "\(name) sent. The server answered again."
            case .timedOut: return "\(name) sent. The server did not answer within 60 seconds."
            }
        }

        /// A model with fixed status rows, for previews.
        static func preview(
            status: ServerControlStatus?, phase: ServerControlPhase = .idle, errorText: String? = nil
        ) -> ServerControlModel {
            let model = ServerControlModel(connections: .preview())
            model.status = status
            model.phase = phase
            model.errorText = errorText
            model.idleRows = [
                ServerStatsRow(label: "Idle", value: "No"),
                ServerStatsRow(label: "Active sessions", value: "0"),
            ]
            return model
        }
    }
#endif
