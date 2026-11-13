import Foundation
import GRDB

/// A New chat before its first message has made it a server chat (board row 104). It belongs to one saved server from
/// the start, and its id is durable, so a message waiting in it survives a relaunch.
public struct PlaceholderChat: Sendable, Equatable, Identifiable {
    /// `new-<UUID>`. The outbox keys the waiting message by it until the server session exists.
    public let id: String
    /// The saved server the chat will start on. It never changes, even if another server becomes active.
    public let connectionID: String
    /// That server's name when the chat was made, for the row.
    public var serverName: String
    /// The server's session, once created. It is saved before anything is sent to it.
    public var sessionID: String?
    public let createdAt: Date

    public init(
        id: String = PlaceholderChat.newID(), connectionID: String, serverName: String, sessionID: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.connectionID = connectionID
        self.serverName = serverName
        self.sessionID = sessionID
        self.createdAt = createdAt
    }

    /// A fresh durable id. A counter would restart at launch and could not key a saved message.
    public static func newID() -> String { "new-\(UUID().uuidString)" }

    /// True for an id made by ``newID()``.
    public static func isPlaceholderID(_ id: String) -> Bool { id.hasPrefix("new-") && id.count > 8 }
}

/// Keeps placeholder chats across a relaunch.
public protocol PlaceholderStore: Sendable {
    func insert(_ chat: PlaceholderChat) async throws
    /// Saves the server session of a placeholder. It returns once the id is written.
    func setSessionID(_ sessionID: String, forPlaceholder id: String) async throws
    func placeholder(id: String) async throws -> PlaceholderChat?
    /// Every placeholder, oldest first.
    func all() async throws -> [PlaceholderChat]
    func remove(id: String) async throws
}

/// The placeholders in the cache database (`placeholder_chats`, made by the `placeholder-chats-v1` migration).
public struct GRDBPlaceholderStore: PlaceholderStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) {
        self.database = database
    }

    public func insert(_ chat: PlaceholderChat) async throws {
        try await database.write { handle in
            try handle.execute(
                sql: """
                    INSERT INTO placeholder_chats (id, connection_id, server_name, session_id, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    chat.id, chat.connectionID, chat.serverName, chat.sessionID, chat.createdAt.timeIntervalSince1970,
                ])
        }
    }

    public func setSessionID(_ sessionID: String, forPlaceholder id: String) async throws {
        try await database.write { handle in
            try handle.execute(
                sql: "UPDATE placeholder_chats SET session_id = ? WHERE id = ?", arguments: [sessionID, id])
        }
    }

    public func placeholder(id: String) async throws -> PlaceholderChat? {
        try await database.read { handle in
            try Row.fetchOne(handle, sql: "SELECT * FROM placeholder_chats WHERE id = ?", arguments: [id])
                .map(Self.chat)
        }
    }

    public func all() async throws -> [PlaceholderChat] {
        try await database.read { handle in
            try Row.fetchAll(handle, sql: "SELECT * FROM placeholder_chats ORDER BY created_at, rowid").map(Self.chat)
        }
    }

    public func remove(id: String) async throws {
        try await database.write { handle in
            try handle.execute(sql: "DELETE FROM placeholder_chats WHERE id = ?", arguments: [id])
        }
    }

    private static func chat(_ row: Row) -> PlaceholderChat {
        PlaceholderChat(
            id: row["id"], connectionID: row["connection_id"], serverName: row["server_name"],
            sessionID: row["session_id"], createdAt: Date(timeIntervalSince1970: row["created_at"]))
    }
}
