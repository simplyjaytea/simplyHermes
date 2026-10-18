import Foundation
import GRDB

/// Keeps offline chats in two tables of the cache database (`offline_chat` and `offline_message`, created by the
/// cache's `offline-chat-v1` migration). The tables are separate from `session` and `message`: the cache mirrors the
/// server, offline chats never reach it, and nothing here reads or writes the server's rows.
///
/// Unlike the rest of the cache, offline chats are not a copy of anything on the server. Deleting the cache file
/// deletes them.
public struct GRDBOfflineChatStore: OfflineChatStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) {
        self.database = database
    }

    public func currentChat(forSession sessionID: String, connection: String) async throws -> OfflineChat? {
        try await database.read { handle in
            try Row.fetchOne(
                handle,
                sql: """
                    SELECT * FROM offline_chat
                    WHERE connection = ? AND session_id = ? AND resolution IS NULL
                    """,
                arguments: [connection, sessionID]
            ).map(Self.chat)
        }
    }

    public func openChat(forSession sessionID: String, connection: String, title: String, at date: Date) async throws
        -> OfflineChat
    {
        let stamp = date.timeIntervalSince1970
        return try await database.write { handle in
            if let row = try Row.fetchOne(
                handle,
                sql: """
                    SELECT * FROM offline_chat
                    WHERE connection = ? AND session_id = ? AND resolution IS NULL
                    """,
                arguments: [connection, sessionID])
            {
                return Self.chat(row)
            }
            let id = UUID().uuidString
            try handle.execute(
                sql: """
                    INSERT INTO offline_chat (connection, chat_id, session_id, title, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [connection, id, sessionID, title, stamp, stamp])
            let when = Date(timeIntervalSince1970: stamp)
            return OfflineChat(id: id, sessionID: sessionID, title: title, createdAt: when, updatedAt: when)
        }
    }

    public func append(
        _ role: OfflineChatMessage.Role, text: String, toChat chatID: String, connection: String, at date: Date
    ) async throws -> OfflineChatMessage {
        let stamp = date.timeIntervalSince1970
        return try await database.write { handle in
            let open = try Int.fetchOne(
                handle,
                sql: "SELECT 1 FROM offline_chat WHERE connection = ? AND chat_id = ? AND resolution IS NULL",
                arguments: [connection, chatID])
            guard open != nil else { throw OfflineChatError.chatClosed }
            let next =
                try Int.fetchOne(
                    handle,
                    sql: """
                        SELECT COALESCE(MAX(message_id), 0) + 1 FROM offline_message
                        WHERE connection = ? AND chat_id = ?
                        """,
                    arguments: [connection, chatID]) ?? 1
            try handle.execute(
                sql: """
                    INSERT INTO offline_message (connection, chat_id, message_id, role, text, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [connection, chatID, next, role.rawValue, text, stamp])
            try handle.execute(
                sql: "UPDATE offline_chat SET updated_at = ? WHERE connection = ? AND chat_id = ?",
                arguments: [stamp, connection, chatID])
            return OfflineChatMessage(
                chatID: chatID, id: next, role: role, text: text, createdAt: Date(timeIntervalSince1970: stamp))
        }
    }

    public func messages(inChat chatID: String, connection: String) async throws -> [OfflineChatMessage] {
        try await database.read { handle in
            try Row.fetchAll(
                handle,
                sql: "SELECT * FROM offline_message WHERE connection = ? AND chat_id = ? ORDER BY message_id",
                arguments: [connection, chatID]
            ).compactMap(Self.message)
        }
    }

    public func resolve(
        chat chatID: String, connection: String, as resolution: OfflineChat.Resolution, at date: Date
    ) async throws {
        let stamp = date.timeIntervalSince1970
        try await database.write { handle in
            try handle.execute(
                sql: """
                    UPDATE offline_chat SET resolution = ?, updated_at = ?
                    WHERE connection = ? AND chat_id = ? AND resolution IS NULL
                    """,
                arguments: [resolution.rawValue, stamp, connection, chatID])
        }
    }

    public func chats(connection: String, limit: Int) async throws -> [OfflineChat] {
        try await database.read { handle in
            try Row.fetchAll(
                handle,
                sql: """
                    SELECT * FROM offline_chat WHERE connection = ?
                    ORDER BY updated_at DESC, created_at DESC, chat_id LIMIT ?
                    """,
                arguments: [connection, limit]
            ).map(Self.chat)
        }
    }

    public func deleteChat(_ chatID: String, connection: String) async throws {
        try await database.write { handle in
            for table in ["offline_message", "offline_chat"] {
                try handle.execute(
                    sql: "DELETE FROM \(table) WHERE connection = ? AND chat_id = ?", arguments: [connection, chatID])
            }
        }
    }

    private static func chat(_ row: Row) -> OfflineChat {
        OfflineChat(
            id: row["chat_id"], sessionID: row["session_id"], title: row["title"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            resolution: (row["resolution"] as String?).flatMap(OfflineChat.Resolution.init(rawValue:)))
    }

    private static func message(_ row: Row) -> OfflineChatMessage? {
        guard let role = OfflineChatMessage.Role(rawValue: row["role"]) else { return nil }
        return OfflineChatMessage(
            chatID: row["chat_id"], id: row["message_id"], role: role, text: row["text"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]))
    }
}
