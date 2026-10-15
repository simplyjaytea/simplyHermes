import Foundation

/// Params of `session.branch`: fork a live session into a new stored child that shares the history so far.
public struct SessionBranchParams: Sendable, Equatable, Codable {
    /// The live session to fork.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// Title of the child.
    public var name: String?
    /// How many messages to copy. The contract does not say more; confirm against a real server before relying on it.
    public var count: Int?
    /// Makes a retry return the first child instead of making another.
    public var idempotencyKey: String?

    /// Creates params. A fresh idempotency key is used when none is given, so a retried call never forks twice.
    public init(
        sessionID: String, profile: String? = nil, name: String? = nil, count: Int? = nil,
        idempotencyKey: String? = UUID().uuidString
    ) {
        self.sessionID = sessionID
        self.profile = profile
        self.name = name
        self.count = count
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case profile, name, count
        case sessionID = "session_id"
        case idempotencyKey = "idempotency_key"
    }
}

/// Result of `session.branch`.
public struct SessionBranchResult: Sendable, Equatable, Codable {
    /// Live id of the child.
    public var sessionID: String
    /// Stored id of the child.
    public var storedSessionID: String
    /// Title of the child.
    public var title: String?
    /// Stored id of the parent.
    public var parent: String?
    /// Messages in the child.
    public var messageCount: Int?
    /// The copied transcript, left raw.
    public var messages: JSONValue?

    enum CodingKeys: String, CodingKey {
        case title, parent, messages
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
        case messageCount = "message_count"
    }
}

extension GatewayClient {
    /// Forks a session. The child is a new stored session with its own live id; open it like any other.
    public func branchSession(_ params: SessionBranchParams) async throws -> SessionBranchResult {
        try await call("session.branch", params: params)
    }
}
