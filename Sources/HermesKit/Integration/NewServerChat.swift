import Foundation

/// Which kind of chat a new chat from outside the chat screens becomes. Siri and Shortcuts, Spotlight, the Share
/// extension and Quick Entry all start chats this way.
public enum NewChatKind: Equatable, Sendable {
    /// A chat on the saved server, made with `session.create`. Hermes answers in it.
    case server
    /// A local chat that only holds text. Hermes never answers in it, so it is only for an app with no saved server.
    case placeholder
}

/// What "New chat" does for Siri and Shortcuts.
public enum NewChatPlan: Equatable, Sendable {
    /// Make a chat on the server and open it. A first message, if there is one, goes into that chat.
    case serverChat
    /// No saved server and no message: open a local chat, as before.
    case placeholderChat
    /// No saved server and a message to send. There is nowhere to send it.
    case needsServer
}

/// The one place that decides how a new chat from outside the chat screens is made.
public enum NewChatPolicy {
    /// A saved server gets a real chat. Without one, the local placeholder is all there is.
    public static func kind(hasServer: Bool) -> NewChatKind {
        hasServer ? .server : .placeholder
    }

    /// The plan for a "New chat" request: whether a server is saved and whether a first message came with it.
    public static func plan(hasServer: Bool, hasText: Bool) -> NewChatPlan {
        switch kind(hasServer: hasServer) {
        case .server: .serverChat
        case .placeholder: hasText ? .needsServer : .placeholderChat
        }
    }
}

// MARK: - Asking the server for a chat

/// The one gateway call that starts a chat. ``GatewayClient`` conforms; tests use a fake.
public protocol SessionCreating: Sendable {
    /// Calls `session.create`.
    func createSession(_ params: SessionCreateParams) async throws -> SessionCreateResult
}

extension GatewayClient: SessionCreating {
    /// Calls `session.create`. A set `profile` wins; otherwise the client adds its active profile, as for every call.
    public func createSession(_ params: SessionCreateParams) async throws -> SessionCreateResult {
        try await call("session.create", params: params, timeout: NewServerChat.requestTimeout)
    }
}

/// A chat the server just made.
public struct StartedChat: Equatable, Sendable {
    /// The durable id. The app lists, opens and resumes a chat by this id.
    public var storedSessionID: String
    /// The live id the server uses in events and in most params.
    public var liveSessionID: String

    public init(storedSessionID: String, liveSessionID: String) {
        self.storedSessionID = storedSessionID
        self.liveSessionID = liveSessionID
    }
}

/// Why a new chat could not be made.
public enum NewChatFailure: Error, Equatable, Sendable {
    /// The server could not be reached: no network, signed out, too old, or the unlock was refused.
    case notReachable
    /// The server answered and said no. `reason` is what it said.
    case refused(reason: String)
}

/// Makes a new chat on the server, through the call the chat screens already use.
public enum NewServerChat {
    /// How long to wait for `session.create` to answer, in seconds. The call only mints a session, so it is quick.
    public static let requestTimeout: Double = 30

    /// Asks the server for a new chat.
    ///
    /// - Parameter profile: the profile (bot) to make the chat under. Nil leaves it to the connection's active profile.
    public static func start(
        using gateway: some SessionCreating, profile: String?
    ) async throws(NewChatFailure) -> StartedChat {
        let result: SessionCreateResult
        do {
            result = try await gateway.createSession(SessionCreateParams(profile: profile))
        } catch let error as RPCError {
            throw .refused(reason: error.message)
        } catch {
            throw .notReachable
        }
        // `stored_session_id` is required by the contract. The session key is the same id in this build.
        guard let stored = result.storedSessionID ?? result.sessionKey, !stored.isEmpty else {
            throw .refused(reason: "The server did not name the new chat.")
        }
        return StartedChat(storedSessionID: stored, liveSessionID: result.sessionID)
    }
}

// MARK: - Waiting for the connection

/// What to do while the saved server connects for a new chat. The app asks again every quarter second.
public enum ConnectWait: Equatable, Sendable {
    /// Connected: ask the server for the chat.
    case proceed
    /// Still connecting. Look again soon.
    case wait
    /// It will not connect in time, or only the user can fix it (sign in again, update the server).
    case giveUp

    /// How long a new chat waits for the server to connect, in seconds.
    public static let patience: TimeInterval = 20

    /// - Parameters:
    ///   - phase: where the connection is now.
    ///   - waited: seconds spent waiting so far.
    public static func next(phase: ConnectionPhase, waited: TimeInterval) -> ConnectWait {
        switch phase {
        case .connected: .proceed
        case .signInRequired, .updateRequired, .failed: .giveUp
        case .idle, .unlocking, .openingTunnel, .checkingServer, .connecting, .reconnecting:
            waited < patience ? .wait : .giveUp
        }
    }
}

// MARK: - Keeping a new chat in the list

/// Chats this app made on the server that the server's chat list does not show yet.
///
/// The server lists a chat once it holds a message. A chat made a moment ago is missing from the list, and a list
/// refresh would drop it from the app while the user is looking at it. This remembers such chats until the server
/// lists them.
public struct StartedChats: Equatable, Sendable {
    private var ids: Set<String> = []

    public init() {}

    /// Remembers a chat the app just made.
    public mutating func note(_ id: String) {
        ids.insert(id)
    }

    /// The remembered chats to keep through a list refresh.
    ///
    /// - Parameters:
    ///   - current: the ids of every chat the app shows now.
    ///   - listed: the ids the server lists now. Such a chat is the server's from here on, so it is forgotten.
    public mutating func kept(among current: [String], listed: Set<String>) -> Set<String> {
        ids.subtract(listed)
        ids.formIntersection(current)
        return ids
    }
}
