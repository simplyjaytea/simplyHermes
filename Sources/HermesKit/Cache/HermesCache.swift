import Foundation
import GRDB

/// A local copy of what the server stored, so a session list and a chat open instantly and offline.
///
/// Everything is scoped by a `connection` key (the saved connection's id), so two servers never mix. The cache
/// only ever mirrors the server: when the server and the cache disagree the server wins and the cache is rewritten.
/// The file lives in the App Group container, so widgets and intents can read it. It is safe to delete, except for
/// the offline chats (``offlineChats``), which exist nowhere else.
public final class HermesCache: Sendable {
    private let database: any DatabaseWriter

    /// Opens or creates the cache at `url`, in WAL mode so readers never wait for the writer.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        database = try DatabasePool(path: url.path, configuration: configuration)
        try Self.migrator.migrate(database)
    }

    /// An in-memory cache for tests and previews.
    public init() throws {
        database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { handle in
            try handle.execute(
                sql: """
                    CREATE TABLE session (
                        connection TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        last_activity REAL NOT NULL,
                        synced_at REAL NOT NULL,
                        json BLOB NOT NULL,
                        PRIMARY KEY (connection, session_id)
                    ) WITHOUT ROWID;
                    CREATE INDEX session_recent ON session (connection, last_activity DESC);
                    CREATE TABLE message (
                        connection TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        row_id INTEGER NOT NULL,
                        json BLOB NOT NULL,
                        PRIMARY KEY (connection, session_id, row_id)
                    ) WITHOUT ROWID;
                    CREATE TABLE reading_position (
                        connection TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        json BLOB NOT NULL,
                        PRIMARY KEY (connection, session_id)
                    ) WITHOUT ROWID;
                    """)
        }
        // Offline chats (WP-65b) are not a copy of the server: they live in their own tables and never join `session`
        // or `message`. At most one chat per server chat is open (`resolution` is null) at a time.
        migrator.registerMigration("offline-chat-v1") { handle in
            try handle.execute(
                sql: """
                    CREATE TABLE offline_chat (
                        connection TEXT NOT NULL,
                        chat_id TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        resolution TEXT,
                        PRIMARY KEY (connection, chat_id)
                    ) WITHOUT ROWID;
                    CREATE UNIQUE INDEX offline_chat_open ON offline_chat (connection, session_id)
                        WHERE resolution IS NULL;
                    CREATE INDEX offline_chat_recent ON offline_chat (connection, updated_at DESC);
                    CREATE TABLE offline_message (
                        connection TEXT NOT NULL,
                        chat_id TEXT NOT NULL,
                        message_id INTEGER NOT NULL,
                        role TEXT NOT NULL,
                        text TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        PRIMARY KEY (connection, chat_id, message_id)
                    ) WITHOUT ROWID;
                    """)
        }
        return migrator
    }

    // MARK: - Sessions

    /// Adds or updates sessions, newest data winning. Sessions not listed stay (a page is not the whole list).
    public func saveSessions(_ sessions: [SessionRecord], connection: String, syncedAt: Date = Date()) async throws {
        let rows = try sessions.map { ($0.id, $0.lastActivityAt ?? $0.startedAt ?? 0, try Self.encoder.encode($0)) }
        try await database.write { handle in
            let statement = try handle.makeStatement(
                sql: """
                    INSERT INTO session (connection, session_id, last_activity, synced_at, json)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT (connection, session_id) DO UPDATE SET
                        last_activity = excluded.last_activity, synced_at = excluded.synced_at, json = excluded.json
                    """)
            for (id, activity, json) in rows {
                try statement.execute(arguments: [connection, id, activity, syncedAt.timeIntervalSince1970, json])
            }
        }
    }

    /// The cached sessions, most recently active first.
    public func sessions(connection: String, limit: Int = 200) async throws -> [SessionRecord] {
        try await database.read { handle in
            let rows = try Data.fetchAll(
                handle,
                sql: "SELECT json FROM session WHERE connection = ? ORDER BY last_activity DESC LIMIT ?",
                arguments: [connection, limit])
            return try rows.map { try Self.decoder.decode(SessionRecord.self, from: $0) }
        }
    }

    /// Forgets one session with its messages and reading position (after a delete on any device).
    public func removeSession(_ id: String, connection: String) async throws {
        try await database.write { handle in
            for table in ["session", "message", "reading_position"] {
                try handle.execute(
                    sql: "DELETE FROM \(table) WHERE connection = ? AND session_id = ?", arguments: [connection, id])
            }
        }
    }

    // MARK: - Messages

    /// Adds or updates stored messages of one session.
    public func saveMessages(_ messages: [StoredMessage], connection: String) async throws {
        let rows = try messages.map { ($0.sessionId, $0.id, try Self.encoder.encode($0)) }
        try await database.write { handle in
            let statement = try handle.makeStatement(
                sql: """
                    INSERT INTO message (connection, session_id, row_id, json) VALUES (?, ?, ?, ?)
                    ON CONFLICT (connection, session_id, row_id) DO UPDATE SET json = excluded.json
                    """)
            for (session, rowID, json) in rows {
                try statement.execute(arguments: [connection, session, rowID, json])
            }
        }
    }

    /// The newest `limit` messages of a session (older than `beforeRowID` when given), oldest first.
    public func messages(
        sessionID: String, connection: String, beforeRowID: Int? = nil, limit: Int = 200
    ) async throws -> [StoredMessage] {
        try await database.read { handle in
            let rows = try Data.fetchAll(
                handle,
                sql: """
                    SELECT json FROM message
                    WHERE connection = ? AND session_id = ? AND row_id < ?
                    ORDER BY row_id DESC LIMIT ?
                    """,
                arguments: [connection, sessionID, beforeRowID ?? Int.max, limit])
            return try rows.reversed().map { try Self.decoder.decode(StoredMessage.self, from: $0) }
        }
    }

    /// How many messages of a session are cached.
    public func messageCount(sessionID: String, connection: String) async throws -> Int {
        try await database.read { handle in
            try Int.fetchOne(
                handle, sql: "SELECT COUNT(*) FROM message WHERE connection = ? AND session_id = ?",
                arguments: [connection, sessionID]) ?? 0
        }
    }

    /// Drops cached messages from `rowID` on, after an edit or rewind cut the session there.
    public func removeMessages(sessionID: String, connection: String, fromRowID rowID: Int) async throws {
        try await database.write { handle in
            try handle.execute(
                sql: "DELETE FROM message WHERE connection = ? AND session_id = ? AND row_id >= ?",
                arguments: [connection, sessionID, rowID])
        }
    }

    /// Replaces all cached messages of a session, for a rebuilt history.
    public func replaceMessages(_ messages: [StoredMessage], sessionID: String, connection: String) async throws {
        try await database.write { handle in
            try handle.execute(
                sql: "DELETE FROM message WHERE connection = ? AND session_id = ?", arguments: [connection, sessionID])
        }
        try await saveMessages(messages, connection: connection)
    }

    // MARK: - Reading position

    /// Saves where the user stopped reading a session.
    public func setReadingPosition(_ position: ReadingPosition, sessionID: String, connection: String) async throws {
        let json = try Self.encoder.encode(position)
        try await database.write { handle in
            try handle.execute(
                sql: """
                    INSERT INTO reading_position (connection, session_id, json) VALUES (?, ?, ?)
                    ON CONFLICT (connection, session_id) DO UPDATE SET json = excluded.json
                    """,
                arguments: [connection, sessionID, json])
        }
    }

    /// Where the user stopped reading a session, if known.
    public func readingPosition(sessionID: String, connection: String) async throws -> ReadingPosition? {
        try await database.read { handle in
            try Data.fetchOne(
                handle, sql: "SELECT json FROM reading_position WHERE connection = ? AND session_id = ?",
                arguments: [connection, sessionID]
            ).map { try Self.decoder.decode(ReadingPosition.self, from: $0) }
        }
    }

    // MARK: - Maintenance

    /// Forgets everything about one connection (when it is deleted or the user signs out), offline chats included.
    public func purge(connection: String) async throws {
        try await database.write { handle in
            for table in ["session", "message", "reading_position", "offline_message", "offline_chat"] {
                try handle.execute(sql: "DELETE FROM \(table) WHERE connection = ?", arguments: [connection])
            }
        }
    }

    // MARK: - Offline chats

    /// The offline chats kept in this database (WP-65b). They share the file but not the rows of the server's data.
    public var offlineChats: GRDBOfflineChatStore { GRDBOfflineChatStore(database: database) }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
