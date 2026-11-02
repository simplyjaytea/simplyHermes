import Foundation
import GRDB

/// Why a local chat could not take a change.
public enum LocalChatError: Error, Sendable, Equatable {
    /// The chat does not exist (it was deleted, or never created).
    case chatNotFound
    /// A reply names a message that is not a user message in the same chat.
    case questionNotFound
}

/// Where local chats are kept. ``HermesCache/localChats`` is the app's implementation; tests may use another.
///
/// A store never touches a server session, and no call takes a connection: a local chat belongs to no server.
public protocol LocalChatStore: Sendable {
    /// The local chats, most recently updated first.
    func chats(limit: Int) async throws -> [LocalChat]

    /// One chat, or nil when it does not exist.
    func chat(_ id: UUID) async throws -> LocalChat?

    /// Creates an empty chat.
    func createChat(id: UUID, title: String, at date: Date) async throws -> LocalChat

    /// The messages of a chat, oldest first.
    func messages(inChat id: UUID) async throws -> [LocalChatMessage]

    /// Adds the user's message to a chat and returns it. Throws ``LocalChatError/chatNotFound`` for a missing chat.
    func appendUserMessage(_ text: String, toChat id: UUID, at date: Date) async throws -> LocalChatMessage

    /// Adds a reply, with the model that wrote it, to a chat and returns it. Throws ``LocalChatError/chatNotFound``
    /// for a missing chat.
    func appendReply(_ reply: LocalReply, toChat id: UUID, at date: Date) async throws -> LocalChatMessage

    /// Deletes a chat with its messages.
    func deleteChat(_ id: UUID) async throws
}

/// Keeps local chats in two tables of the cache database, `local_chats` and `local_messages` (created by the cache's
/// `local-chat-v1` migration). Nothing here reads or writes the server's rows.
///
/// The model that wrote a reply is stored in three columns (`answered_by_kind`, `answered_by_id`,
/// `answered_by_name`). `kind` is `apple` or `downloaded`; a migrated reply with no record has a null kind.
public struct GRDBLocalChatStore: LocalChatStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) {
        self.database = database
    }

    public func chats(limit: Int) async throws -> [LocalChat] {
        try await database.read { handle in
            try Row.fetchAll(
                handle,
                sql: "SELECT * FROM local_chats ORDER BY updated_at DESC, created_at DESC, chat_id LIMIT ?",
                arguments: [limit]
            ).compactMap(Self.chat)
        }
    }

    public func chat(_ id: UUID) async throws -> LocalChat? {
        try await database.read { handle in
            try Row.fetchOne(
                handle, sql: "SELECT * FROM local_chats WHERE chat_id = ?", arguments: [id.uuidString]
            ).flatMap(Self.chat)
        }
    }

    public func createChat(id: UUID, title: String, at date: Date) async throws -> LocalChat {
        let stamp = date.timeIntervalSince1970
        try await database.write { handle in
            try handle.execute(
                sql: "INSERT INTO local_chats (chat_id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
                arguments: [id.uuidString, title, stamp, stamp])
        }
        return LocalChat(id: id, title: title, createdAt: date, updatedAt: date)
    }

    public func messages(inChat id: UUID) async throws -> [LocalChatMessage] {
        try await database.read { handle in
            try Row.fetchAll(
                handle,
                sql: "SELECT * FROM local_messages WHERE chat_id = ? ORDER BY message_id",
                arguments: [id.uuidString]
            ).compactMap(Self.message)
        }
    }

    public func appendUserMessage(_ text: String, toChat id: UUID, at date: Date) async throws -> LocalChatMessage {
        try await append(.user, text: text, toChat: id, at: date)
    }

    public func appendReply(_ reply: LocalReply, toChat id: UUID, at date: Date) async throws -> LocalChatMessage {
        let author = LocalChatMessage.Author.assistant(answeredBy: reply.answeredBy, inReplyTo: reply.inReplyTo)
        return try await append(author, text: reply.text, toChat: id, at: date)
    }

    public func deleteChat(_ id: UUID) async throws {
        try await database.write { handle in
            try handle.execute(sql: "DELETE FROM local_messages WHERE chat_id = ?", arguments: [id.uuidString])
            try handle.execute(sql: "DELETE FROM local_chats WHERE chat_id = ?", arguments: [id.uuidString])
        }
    }

    private func append(
        _ author: LocalChatMessage.Author, text: String, toChat id: UUID, at date: Date
    ) async throws -> LocalChatMessage {
        let stamp = date.timeIntervalSince1970
        let (role, model) = Self.columns(author)
        return try await database.write { handle in
            guard
                try Int.fetchOne(
                    handle, sql: "SELECT 1 FROM local_chats WHERE chat_id = ?", arguments: [id.uuidString]) != nil
            else { throw LocalChatError.chatNotFound }
            // A reply must answer a user message of the same chat, or the question it answers cannot be found again.
            if let question = Self.questionID(author) {
                guard
                    try Int.fetchOne(
                        handle,
                        sql: "SELECT 1 FROM local_messages WHERE chat_id = ? AND message_id = ? AND role = 'user'",
                        arguments: [id.uuidString, question]) != nil
                else { throw LocalChatError.questionNotFound }
            }
            let next =
                try Int.fetchOne(
                    handle,
                    sql: "SELECT COALESCE(MAX(message_id), 0) + 1 FROM local_messages WHERE chat_id = ?",
                    arguments: [id.uuidString]) ?? 1
            try handle.execute(
                sql: """
                    INSERT INTO local_messages
                        (chat_id, message_id, role, text, answered_by_kind, answered_by_id, answered_by_name, reply_to,
                         created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id.uuidString, next, role, text, model.kind, model.id, model.name, Self.questionID(author), stamp,
                ])
            try handle.execute(
                sql: "UPDATE local_chats SET updated_at = ? WHERE chat_id = ?", arguments: [stamp, id.uuidString])
            return LocalChatMessage(
                chatID: id, id: next, author: author, text: text, createdAt: Date(timeIntervalSince1970: stamp))
        }
    }

    private struct ModelColumns {
        let kind: String?
        let id: String?
        let name: String?
    }

    private static func columns(_ author: LocalChatMessage.Author) -> (role: String, model: ModelColumns) {
        switch author {
        case .user:
            return ("user", ModelColumns(kind: nil, id: nil, name: nil))
        case .assistant(let identity, _):
            switch identity {
            case .apple:
                return ("assistant", ModelColumns(kind: "apple", id: nil, name: nil))
            case .downloaded(let id, let name):
                return ("assistant", ModelColumns(kind: "downloaded", id: id, name: name))
            case nil:
                return ("assistant", ModelColumns(kind: nil, id: nil, name: nil))
            }
        }
    }

    /// The question a reply answers, or nil for a user message.
    private static func questionID(_ author: LocalChatMessage.Author) -> Int? {
        if case .assistant(_, let question) = author { return question }
        return nil
    }

    /// A chat from its row. A row whose id is not a UUID is skipped, not given a new id: a new id would make its
    /// messages unreachable on the next read.
    private static func chat(_ row: Row) -> LocalChat? {
        guard let id = UUID(uuidString: row["chat_id"]) else { return nil }
        return LocalChat(
            id: id,
            title: row["title"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]))
    }

    private static func message(_ row: Row) -> LocalChatMessage? {
        let author: LocalChatMessage.Author
        switch row["role"] as String {
        case "user":
            author = .user
        case "assistant":
            author = .assistant(answeredBy: identity(row), inReplyTo: row["reply_to"] as Int?)
        default:
            return nil
        }
        guard let chatID = UUID(uuidString: row["chat_id"]) else { return nil }
        return LocalChatMessage(
            chatID: chatID, id: row["message_id"], author: author, text: row["text"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]))
    }

    private static func identity(_ row: Row) -> ModelIdentity? {
        switch row["answered_by_kind"] as String? {
        case "apple":
            return .apple
        case "downloaded":
            guard let id = row["answered_by_id"] as String?, let name = row["answered_by_name"] as String? else {
                return nil
            }
            return .downloaded(id: id, displayName: name)
        default:
            return nil
        }
    }
}
