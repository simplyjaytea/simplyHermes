import Foundation

/// A chat that lives only on this iPhone (WP-7). It has no server session, works with no server configured, and is
/// answered only by an on-device model. Its id is the ``ChatBackend/local(chatID:)`` of the chat.
public struct LocalChat: Sendable, Equatable, Identifiable {
    /// The title of a chat whose first message has no text to cut a title from.
    public static let fallbackTitle = "Local chat"

    /// Unique id.
    public let id: UUID
    /// Short title, cut from the first message.
    public var title: String
    /// When the chat started.
    public var createdAt: Date
    /// When the last message was added.
    public var updatedAt: Date

    /// Creates a chat.
    public init(id: UUID, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

/// One message of a local chat.
public struct LocalChatMessage: Sendable, Equatable, Identifiable {
    /// Who wrote it. Only a reply carries the model that wrote it.
    public enum Author: Sendable, Equatable {
        /// The person using the app.
        case user
        /// The on-device model. `answeredBy` is nil only for a reply saved before the app recorded models (migrated from
        /// the offline chat of WP-65b). Every reply written by ``LocalChatController`` has one.
        case assistant(answeredBy: ModelIdentity?)
    }

    /// The chat it belongs to.
    public let chatID: UUID
    /// Position in the chat, from 1. Unique within the chat.
    public let id: Int
    /// Who wrote it.
    public let author: Author
    /// The text.
    public let text: String
    /// When it was written.
    public let createdAt: Date

    /// Creates a message.
    public init(chatID: UUID, id: Int, author: Author, text: String, createdAt: Date) {
        self.chatID = chatID
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
    }
}

/// A reply from an on-device model, with the model that wrote it. A reply is saved only as one of these, so a local
/// row always names its model.
public struct LocalReply: Sendable, Equatable {
    /// The reply text, already trimmed and not empty.
    public let text: String
    /// The model that wrote it.
    public let answeredBy: ModelIdentity

    /// Creates a reply.
    public init(text: String, answeredBy: ModelIdentity) {
        self.text = text
        self.answeredBy = answeredBy
    }
}
