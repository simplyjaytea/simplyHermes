#if canImport(UIKit)
    import HermesKit
    import Observation

    /// Where the fleet update stands.
    public enum FleetUpdatePhase: Sendable, Equatable {
        case idle
        /// The servers run one at a time. `position` counts from 1. `name` is nil until the first server starts.
        case running(position: Int, total: Int, name: String?)
        /// Every saved server has a line in the result list.
        case finished
    }

    /// Update all servers (Settings > Server > Update all servers): the check, then the update when one exists, on
    /// every saved server, one at a time. Each server gets one line in the result list (WP-54).
    @MainActor
    @Observable
    public final class FleetUpdateModel {
        /// One line per server from the last run, in the order the servers ran.
        public private(set) var entries: [FleetUpdateEntry] = []
        public private(set) var phase: FleetUpdatePhase = .idle
        /// Set when the run could not start.
        public private(set) var errorText: String?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let clock: any GatewayClock

        public init(connections: ConnectionsModel, clock: any GatewayClock = SystemGatewayClock()) {
            self.connections = connections
            self.clock = clock
        }

        /// The saved servers, in the order the list shows them.
        public var servers: [ServerConnection] {
            connections.connections
        }

        /// True while the servers run, so the button stays off.
        public var isBusy: Bool {
            if case .running = phase { return true }
            return false
        }

        /// Runs the check, then the update when one exists, on every saved server. A server that fails gets its own
        /// line, and the next server still runs.
        public func run() async {
            guard !isBusy else { return }
            let servers = self.servers
            guard !servers.isEmpty else { return }
            guard let manager = connections.manager else {
                errorText = "Servers are not ready yet. Try again in a moment."
                return
            }
            let clock = self.clock
            errorText = nil
            entries = []
            phase = .running(position: 0, total: servers.count, name: nil)
            entries = await FleetUpdateRunner.run(servers) { [weak self] server in
                await self?.began(server, in: servers)
                let backend = ServerControlBackend(manager: manager, connection: server)
                return try await HermesUpdateFlow().checkAndApply(backend.updateSteps(), clock: clock)
            }
            phase = .finished
        }

        /// Marks which server runs now.
        private func began(_ server: ServerConnection, in servers: [ServerConnection]) {
            let position = (servers.firstIndex { $0.id == server.id } ?? 0) + 1
            phase = .running(position: position, total: servers.count, name: server.name)
        }

        /// The line for one server's result.
        static func summary(_ state: FleetUpdateState) -> String {
            switch state {
            case .done(.upToDate):
                return "Up to date."
            case .done(.manualUpdateNeeded(let command, let message)):
                if let message { return message }
                if let command { return "An update exists. Run \(command) on the server." }
                return "An update exists. Update it by hand on the server."
            case .done(.checkUnclear(let message)):
                return message ?? "The check could not tell whether an update exists."
            case .done(.finished(let compatibility, _)):
                return "Updated. " + HermesUpdateModel.versionText(compatibility)
            case .done(.timedOut):
                return "The update did not finish within 15 minutes. Check the server."
            case .failed(let text):
                return text
            case .stopped:
                return "Not run. The run stopped before this server."
            }
        }

        /// True when the line needs the user's attention.
        static func isProblem(_ state: FleetUpdateState) -> Bool {
            switch state {
            case .failed, .done(.timedOut): return true
            case .done, .stopped: return false
            }
        }

        /// Sample results for previews: one server updated, one that did not answer.
        static var sampleEntries: [FleetUpdateEntry] {
            let servers = ConnectionsModel.sampleConnections
            return [
                FleetUpdateEntry(
                    server: servers[0],
                    state: .done(.finished(compatibility: .compatible, receipt: .null))),
                FleetUpdateEntry(server: servers[1], state: .failed("The server did not answer.")),
            ]
        }

        /// A model with fixed results, for previews.
        static func preview(
            entries: [FleetUpdateEntry] = [], phase: FleetUpdatePhase = .idle, errorText: String? = nil
        ) -> FleetUpdateModel {
            let model = FleetUpdateModel(connections: .preview())
            model.entries = entries
            model.phase = phase
            model.errorText = errorText
            return model
        }
    }
#endif
