import Foundation
import GRDB

/// Keeps the outbox in the `outbound_messages` table of the cache database (created by the cache's `outbox-v1`
/// migration). Each row holds the whole record as JSON, plus the chat and state columns the queries need.
///
/// Unlike the server's data, an unsent message exists nowhere else. Deleting the cache file deletes it.
public struct GRDBOutboxStore: OutboxStore {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter) {
        self.database = database
    }

    public func insert(_ record: OutboundRecord) async throws {
        let json = try Self.encoder.encode(record)
        try await database.write { handle in
            try handle.execute(
                sql: """
                    INSERT INTO outbound_messages (id, connection_id, chat_id, state, created_at, json)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString, record.connectionID, record.chatID, record.state.kind,
                    record.createdAt.timeIntervalSince1970, json,
                ])
        }
    }

    @discardableResult
    public func updateState(_ state: DeliveryState, forID id: UUID) async throws -> OutboundRecord {
        try await database.write { handle in
            guard
                let stored = try Data.fetchOne(
                    handle, sql: "SELECT json FROM outbound_messages WHERE id = ?", arguments: [id.uuidString])
            else {
                throw OutboxError.notFound(id)
            }
            var record = try Self.decoder.decode(OutboundRecord.self, from: stored)
            try record.move(to: state)
            try handle.execute(
                sql: "UPDATE outbound_messages SET state = ?, json = ? WHERE id = ?",
                arguments: [record.state.kind, try Self.encoder.encode(record), id.uuidString])
            return record
        }
    }

    public func records(inChat chatID: String) async throws -> [OutboundRecord] {
        try await database.read { handle in
            let rows = try Data.fetchAll(
                handle,
                sql: "SELECT json FROM outbound_messages WHERE chat_id = ? ORDER BY created_at, rowid",
                arguments: [chatID])
            return try rows.map { try Self.decoder.decode(OutboundRecord.self, from: $0) }
        }
    }

    @discardableResult
    public func pruneSent(inChat chatID: String) async throws -> Int {
        try await database.write { handle in
            try handle.execute(
                sql: "DELETE FROM outbound_messages WHERE chat_id = ? AND state = 'sent'", arguments: [chatID])
            return handle.changesCount
        }
    }

    public func remove(id: UUID) async throws {
        try await database.write { handle in
            try handle.execute(sql: "DELETE FROM outbound_messages WHERE id = ?", arguments: [id.uuidString])
        }
    }

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
