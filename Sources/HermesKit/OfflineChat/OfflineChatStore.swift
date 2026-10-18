import Foundation

/// One message of an offline chat.
public struct OfflineChatMessage: Sendable, Equatable, Identifiable {
    /// Who wrote it.
    public enum Role: String, Sendable, Equatable {
        /// The person using the app.
        case user
        /// The on-device model.
        case assistant
    }

    /// The chat it belongs to.
    public let chatID: String
    /// Position in the chat, from 1. Unique within the chat.
    public let id: Int
    /// Who wrote it.
    public let role: Role
    /// The text.
    public let text: String
    /// When it was written.
    public let createdAt: Date

    /// Creates a message.
    public init(chatID: String, id: Int, role: Role, text: String, createdAt: Date) {
        self.chatID = chatID
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// A chat held with the on-device model while the server was out of reach (plan Q44).
///
/// It belongs to one server chat (``sessionID``) but is stored apart from it: nothing in an offline chat is ever
/// written to the server session. It stays open until the user answers the "Send to Hermes" offer after the
/// connection is back; then it is closed, and the next offline message starts a new one.
public struct OfflineChat: Sendable, Equatable, Identifiable {
    /// How the user closed a chat.
    public enum Resolution: String, Sendable, Equatable {
        /// The last prompt was sent to Hermes.
        case sent
        /// The offer was dismissed.
        case dismissed
    }

    /// Titles used when the first prompt has no text to cut a title from.
    public static let fallbackTitle = "Offline chat"

    /// Unique id.
    public let id: String
    /// The server chat (stored session id) the user was in.
    public let sessionID: String
    /// Short title, cut from the first prompt.
    public var title: String
    /// When the chat started.
    public var createdAt: Date
    /// When the last message was added or the chat was closed.
    public var updatedAt: Date
    /// How the chat was closed. Nil while it is open.
    public var resolution: Resolution?

    /// True while the chat takes new messages.
    public var isOpen: Bool { resolution == nil }

    /// Creates a chat.
    public init(
        id: String, sessionID: String, title: String, createdAt: Date, updatedAt: Date, resolution: Resolution? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolution = resolution
    }

    /// A title from the first line of `prompt`, cut to ``LocalHelpers/maxTitleLength`` characters.
    public static func title(forPrompt prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackTitle }
        guard trimmed.count > LocalHelpers.maxTitleLength else { return trimmed }
        return String(trimmed.prefix(LocalHelpers.maxTitleLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// Why an offline chat could not take a change.
public enum OfflineChatError: Error, Sendable, Equatable {
    /// The chat is closed or does not exist.
    case chatClosed
}

/// Where offline chats are kept. ``HermesCache/offlineChats`` is the app's implementation; tests may use another.
///
/// Every call is scoped by `connection` (the saved connection's id), like the rest of the cache, so two servers never
/// mix. A store never touches server sessions or their messages.
public protocol OfflineChatStore: Sendable {
    /// The open offline chat of a server chat, or nil when none was started or the last one was closed.
    func currentChat(forSession sessionID: String, connection: String) async throws -> OfflineChat?

    /// The open offline chat of a server chat. Starts one called `title` when there is none.
    func openChat(forSession sessionID: String, connection: String, title: String, at date: Date) async throws
        -> OfflineChat

    /// Adds a message to an open chat and returns it. Throws ``OfflineChatError/chatClosed`` when the chat is closed
    /// or gone.
    func append(
        _ role: OfflineChatMessage.Role, text: String, toChat chatID: String, connection: String, at date: Date
    ) async throws -> OfflineChatMessage

    /// The messages of a chat, oldest first.
    func messages(inChat chatID: String, connection: String) async throws -> [OfflineChatMessage]

    /// Closes a chat. A chat that is already closed keeps its first resolution.
    func resolve(chat chatID: String, connection: String, as resolution: OfflineChat.Resolution, at date: Date)
        async throws

    /// The offline chats of a connection, most recently updated first. For the sessions list.
    func chats(connection: String, limit: Int) async throws -> [OfflineChat]

    /// Deletes a chat with its messages.
    func deleteChat(_ chatID: String, connection: String) async throws
}
