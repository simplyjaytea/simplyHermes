import Foundation

/// The saved server changed while a New chat waited for its first message to be made. Nothing was sent: the message
/// stays where the user typed it.
public struct NewChatServerChanged: Error, Equatable, Sendable {
    /// The server the message was written for.
    public var serverName: String

    public init(serverName: String) {
        self.serverName = serverName
    }
}

/// Makes the server chat for a New chat's first message, on the server the message was written for and nowhere else.
///
/// The wait for the server can last 20 seconds (``ConnectWait``). The user may switch servers meanwhile, and the screen
/// then reads the *active* server. So the server is fixed when the user sends, and this checks, after the wait and
/// again after the session exists, that it is still the active one. If it is not, nothing is handed on: the text stays
/// in the composer, and an empty chat made on the first server is left there, where it holds nothing and lists nothing.
public enum NewChatStarter {
    /// - Parameters:
    ///   - bound: the server the message was written for.
    ///   - active: the active server now.
    ///   - wait: connects `bound` and waits for it (``ConnectWait/connected(connect:phase:now:pause:)``). True when
    ///     connected.
    ///   - create: makes the empty chat on `bound` and returns its session id.
    /// - Returns: the session id, or nil when `bound` did not connect (the caller says why).
    /// - Throws: ``NewChatServerChanged`` when the active server is no longer `bound`.
    public static func start(
        bound: String, serverName: String, active: @Sendable () async -> String?,
        wait: @Sendable () async -> Bool, create: @Sendable () async throws -> String
    ) async throws -> String? {
        guard await wait() else { return nil }
        guard await active() == bound else { throw NewChatServerChanged(serverName: serverName) }
        let session = try await create()
        // The create is a round trip too. A switch during it still must not hand the chat to the other server.
        guard await active() == bound else { throw NewChatServerChanged(serverName: serverName) }
        return session
    }
}
