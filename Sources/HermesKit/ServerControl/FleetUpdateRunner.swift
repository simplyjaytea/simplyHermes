import Foundation

/// Where one server stood in a fleet update.
public enum FleetUpdateState: Sendable, Equatable {
    /// The run ended in this outcome.
    case done(HermesUpdateRunOutcome)
    /// The run failed on this server. The text is for the user.
    case failed(String)
    /// The run was cancelled before this server.
    case stopped
}

/// One line of the fleet update's result list.
public struct FleetUpdateEntry: Sendable, Equatable, Identifiable {
    /// The saved server.
    public var server: ServerConnection
    /// What happened there.
    public var state: FleetUpdateState

    /// Creates an entry.
    public init(server: ServerConnection, state: FleetUpdateState) {
        self.server = server
        self.state = state
    }

    /// The server's id.
    public var id: UUID { server.id }
}

/// Runs the update check and update on every saved server, one at a time, in the order given.
public enum FleetUpdateRunner {
    /// Calls `step` for each server in turn. A failure on one server is recorded and the next server still runs.
    /// Cancelling the task stops after the current server; the rest are ``FleetUpdateState/stopped``.
    public static func run(
        _ servers: [ServerConnection], step: @Sendable (ServerConnection) async throws -> HermesUpdateRunOutcome
    ) async -> [FleetUpdateEntry] {
        var entries: [FleetUpdateEntry] = []
        for (index, server) in servers.enumerated() {
            if Task.isCancelled {
                entries += servers[index...].map { FleetUpdateEntry(server: $0, state: .stopped) }
                break
            }
            do {
                let outcome = try await step(server)
                entries.append(FleetUpdateEntry(server: server, state: .done(outcome)))
            } catch {
                let state: FleetUpdateState = Task.isCancelled ? .stopped : .failed(ServerControlError.describe(error))
                entries.append(FleetUpdateEntry(server: server, state: state))
            }
        }
        return entries
    }
}
