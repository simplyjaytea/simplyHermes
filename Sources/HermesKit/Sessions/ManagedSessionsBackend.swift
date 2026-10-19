import Foundation

/// A ``SessionsBackend`` for a saved connection. It asks the ``ConnectionManager`` for the signed-in REST client on
/// every call, so the list can read its cache offline and connects only when it needs the server.
public struct ManagedSessionsBackend: SessionsBackend {
    private let manager: ConnectionManager
    private let connection: ServerConnection

    /// Creates a backend for `connection`.
    public init(manager: ConnectionManager, connection: ServerConnection) {
        self.manager = manager
        self.connection = connection
    }

    /// Connects on demand and returns the REST client. Throws ``ConnectionUnavailable`` when it cannot connect.
    private func rest() async throws -> RESTClient {
        _ = try await manager.client(for: connection)
        guard let rest = await manager.rest(for: connection.id) else {
            throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
        }
        return rest
    }

    public func sessions(limit: Int, offset: Int, archived: Bool) async throws -> SessionList {
        try await rest().sessions(limit: limit, offset: offset, archived: archived)
    }

    public func searchSessions(_ text: String, limit: Int) async throws -> SessionSearchResults {
        try await rest().searchSessions(text, limit: limit)
    }

    public func updateSession(id: String, _ update: SessionUpdate) async throws {
        try await rest().updateSession(id: id, update)
    }

    public func deleteSession(id: String) async throws {
        try await rest().deleteSession(id: id)
    }

    public func session(id: String, profile: String) async throws -> SessionRecord {
        try await rest().session(id: id, profile: profile)
    }

    public func exportSession(id: String, profile: String?) async throws -> Data {
        try await rest().exportSession(id: id, profile: profile)
    }

    public func pruneSessions(_ filter: SessionPruneFilter) async throws -> JSONValue {
        try await rest().pruneSessions(filter)
    }
}
