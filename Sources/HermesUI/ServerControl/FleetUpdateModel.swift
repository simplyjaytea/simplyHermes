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

    /// The answer to the question a fleet update asks before one server's update.
    public enum FleetUpdateAnswer: Sendable, Equatable {
        /// Update this server now.
        case update
        /// Leave this server as it is and go on to the next one.
        case skip
        /// Leave this server and every later one as they are. The run ends.
        case stop
    }

    /// The server whose update waits for the user's answer, and the check that found the update.
    struct FleetUpdateQuestion: Sendable, Equatable {
        let server: ServerConnection
        let check: HermesUpdateCheck
    }

    /// Update all servers (Settings > Server > Update all servers): the check on every saved server, one at a time. A
    /// server with an update asks first, and its update runs only when the user says Update. Each server gets one line
    /// in the result list (WP-54).
    @MainActor
    @Observable
    public final class FleetUpdateModel {
        /// One line per server from the last run, in the order the servers ran.
        public private(set) var entries: [FleetUpdateEntry] = []
        public private(set) var phase: FleetUpdatePhase = .idle
        /// Set when the run could not start.
        public private(set) var errorText: String?
        /// The update that waits for the answer. Nil when no question is open.
        private(set) var question: FleetUpdateQuestion?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let clock: any GatewayClock
        /// The task of the run. Stop cancels it.
        @ObservationIgnored private var runTask: Task<Void, Never>?
        /// Resumes the run with the answer to `question`: true for Update.
        @ObservationIgnored private var resumeQuestion: CheckedContinuation<Bool, Never>?

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

        /// Starts the run in a task the model keeps, so Stop can cancel it. A start while a run goes on does nothing.
        public func start() {
            guard runTask == nil else { return }
            runTask = Task {
                await self.run()
                self.runTask = nil
            }
        }

        /// The answer to the open question. Update and Skip let the run go on. Stop cancels the run, so no later
        /// server starts.
        public func answer(_ choice: FleetUpdateAnswer) {
            guard let continuation = resumeQuestion else { return }
            resumeQuestion = nil
            question = nil
            if choice == .stop { runTask?.cancel() }
            continuation.resume(returning: choice == .update)
        }

        /// The dialog closed without a button, which counts as Stop.
        public func dismissQuestion() {
            answer(.stop)
        }

        /// Runs the check on every saved server, one at a time. A server that fails gets its own line, and the next
        /// server still runs.
        private func run() async {
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
            // The servers this run connects keep the last used server as it is.
            connections.recordsLastUsed = false
            entries = await FleetUpdateRunner.run(servers) { [weak self] server in
                guard let self else { throw CancellationError() }
                await self.began(server, in: servers)
                return try await self.checkAndUpdate(server, manager: manager, clock: clock)
            }
            connections.recordsLastUsed = true
            phase = .finished
        }

        /// One server's check, then its update when the user says Update. A connection the run had to open is closed
        /// again afterwards, so no tunnel, socket or remote `hermes serve` process stays behind.
        private func checkAndUpdate(
            _ server: ServerConnection, manager: ConnectionManager, clock: any GatewayClock
        ) async throws -> HermesUpdateRunOutcome {
            let opened = await manager.phase(of: server.id).acceptsConnect
            let backend = ServerControlBackend(manager: manager, connection: server)
            let outcome: HermesUpdateRunOutcome
            do {
                outcome = try await HermesUpdateFlow().checkAndApply(backend.updateSteps(), clock: clock) { check in
                    await self.askToUpdate(server, check)
                }
            } catch {
                if opened { await manager.disconnect(server.id) }
                throw error
            }
            if opened { await manager.disconnect(server.id) }
            return outcome
        }

        /// Asks whether to update one server, and waits for the answer. The run waits here, so no later server starts.
        private func askToUpdate(_ server: ServerConnection, _ check: HermesUpdateCheck) async -> Bool {
            await withCheckedContinuation { continuation in
                resumeQuestion = continuation
                question = FleetUpdateQuestion(server: server, check: check)
            }
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
            case .done(.skipped):
                return "Skipped. Nothing was changed."
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
