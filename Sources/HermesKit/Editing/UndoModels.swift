import Foundation

/// Params of `session.undo`: drops the last user turn and everything after it from an idle session.
/// Checked live against the testbed (WP-03): it removes turns without sending text.
public struct SessionUndoParams: Sendable, Equatable, Codable {
    /// The live session to cut.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates params.
    public init(sessionID: String, profile: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
    }
}

/// Result of `session.undo`: how many messages it removed.
public struct SessionUndoResult: Sendable, Equatable, Codable {
    /// Messages removed, the user turn and its replies.
    public var removed: Int
}

extension GatewayClient {
    /// Drops the last user turn from an idle session. Call once per turn to cut further back.
    public func undoSession(_ params: SessionUndoParams) async throws -> SessionUndoResult {
        try await call("session.undo", params: params)
    }
}
