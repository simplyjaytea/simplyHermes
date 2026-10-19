import Foundation

/// Params of `session.workspace.move`: re-homes a stored session into another folder (WP-37).
/// Checked live against the testbed: `session_key` takes the stored session id from the session list.
public struct SessionWorkspaceMoveParams: Sendable, Equatable, Codable {
    /// The stored session to move.
    public var sessionKey: String
    /// The folder on the server the session moves into.
    public var cwd: String
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates params.
    public init(sessionKey: String, cwd: String, profile: String? = nil) {
        self.sessionKey = sessionKey
        self.cwd = cwd
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionKey = "session_key"
        case cwd
    }
}

/// Result of `session.workspace.move`: the folder now in use and its git state.
public struct SessionWorkspaceMoveResult: Sendable, Equatable, Codable {
    /// The folder the session runs in now.
    public var cwd: String
    /// Git branch of that folder, when it is a repo.
    public var branch: String?
    /// Root of the git repo that holds the folder, when there is one.
    public var gitRepoRoot: String?

    enum CodingKeys: String, CodingKey {
        case cwd
        case branch
        case gitRepoRoot = "git_repo_root"
    }
}

extension GatewayClient {
    /// Moves a stored session into another folder. A live agent follows the change.
    public func moveSessionWorkspace(_ params: SessionWorkspaceMoveParams) async throws -> SessionWorkspaceMoveResult {
        try await call("session.workspace.move", params: params)
    }
}
