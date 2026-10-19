/// `session.create` answered without a stored id, so the new chat cannot be resumed.
public struct MissingStoredSessionError: Error, Equatable, Sendable {
    public init() {}
}

extension GatewayClient {
    /// Creates an empty chat on the server and returns its stored id. `session.resume` opens it later.
    public func createEmptySession() async throws -> String {
        let result: SessionCreateResult = try await call("session.create", params: SessionCreateParams())
        guard let stored = result.storedSessionID ?? result.sessionKey else { throw MissingStoredSessionError() }
        return stored
    }
}
