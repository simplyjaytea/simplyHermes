import Foundation
import GRDB
import Testing

@testable import HermesKit

struct OutboxStoreTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(
        _ text: String, chat: String = "c1", connection: String = "x", at offset: Double = 0
    ) -> OutboundRecord {
        OutboundRecord(connectionID: connection, chatID: chat, text: text, createdAt: start.addingTimeInterval(offset))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
    }

    // MARK: - State machine

    @Test func onlyTheDocumentedMovesAreAllowed() {
        let all: [DeliveryState] = [.pending, .sending, .sent(acknowledgedAt: start), .failed(reason: "offline")]
        let allowed: Set<String> = [
            "pending>sending", "pending>failed",
            "sending>sent", "sending>failed", "sending>pending",
            "failed>pending",
        ]
        for from in all {
            for next in all {
                let move = "\(from.kind)>\(next.kind)"
                #expect(from.canMove(to: next) == allowed.contains(move), "\(move)")
            }
        }
    }

    @Test func sentIsTerminalAndIllegalMovesThrow() throws {
        var message = record("hello")
        #expect(throws: OutboxError.self) { try message.move(to: .sent(acknowledgedAt: start)) }
        #expect(message.state == .pending)

        try message.move(to: .sending)
        #expect(message.attempts == 1)
        try message.move(to: .sent(acknowledgedAt: start))
        #expect(throws: OutboxError.self) { try message.move(to: .sending) }
        #expect(message.state == .sent(acknowledgedAt: start))
        #expect(message.attempts == 1)
    }

    @Test func aRetryAfterFailureCountsAnotherAttempt() throws {
        var message = record("hello")
        try message.move(to: .sending)
        try message.move(to: .failed(reason: "Can't reach the server"))
        try message.move(to: .pending)
        try message.move(to: .sending)
        #expect(message.attempts == 2)
    }

    // MARK: - Store

    @Test func aRecordSurvivesReopeningTheDatabase() async throws {
        let url = temporaryURL()
        let saved = record("kept over a relaunch")
        do {
            let cache = try HermesCache(url: url)
            try await cache.outbox.insert(saved)
        }
        let reopened = try HermesCache(url: url)
        #expect(try await reopened.outbox.records(inChat: "c1") == [saved])
    }

    /// A chat whose first message still waits is not in the server's list, so the shell asks the outbox for it.
    @Test func unsentChatsAreListedPerServerOldestFirstWithoutSentOnes() async throws {
        let outbox = try HermesCache().outbox
        let sent = record("done", chat: "sent-chat")
        try await outbox.insert(record("first", chat: "b"))
        try await outbox.insert(record("second", chat: "a"))
        try await outbox.insert(record("again", chat: "b"))
        try await outbox.insert(record("other server", chat: "c", connection: "y"))
        try await outbox.insert(record("not made yet", chat: "new-11111111-1111-1111-1111-111111111111"))
        try await outbox.insert(sent)
        try await outbox.updateState(.sending, forID: sent.id)
        try await outbox.updateState(.sent(acknowledgedAt: start), forID: sent.id)

        #expect(
            try await outbox.unsentChatIDs(connection: "x") == ["b", "a", "new-11111111-1111-1111-1111-111111111111"])
        #expect(try await outbox.unsentServerChatIDs(connection: "x") == ["b", "a"])
        #expect(try await outbox.unsentChatIDs(connection: "y") == ["c"])
        #expect(try await outbox.unsentChatIDs(connection: "z").isEmpty)
    }

    @Test func aStateChangeSurvivesReopeningTheDatabase() async throws {
        let url = temporaryURL()
        let saved = record("hello")
        let acknowledged = DeliveryState.sent(acknowledgedAt: start.addingTimeInterval(3))
        do {
            let cache = try HermesCache(url: url)
            try await cache.outbox.insert(saved)
            try await cache.outbox.updateState(.sending, forID: saved.id)
            try await cache.outbox.updateState(acknowledged, forID: saved.id)
        }
        let loaded = try await HermesCache(url: url).outbox.records(inChat: "c1")
        #expect(loaded.map(\.state) == [acknowledged])
        #expect(loaded.map(\.attempts) == [1])
    }

    @Test func theStoreRefusesIllegalMovesAndLeavesTheRowAlone() async throws {
        let cache = try HermesCache()
        let saved = record("hello")
        try await cache.outbox.insert(saved)

        await #expect(throws: OutboxError.self) {
            try await cache.outbox.updateState(.sent(acknowledgedAt: self.start), forID: saved.id)
        }
        #expect(try await cache.outbox.records(inChat: "c1") == [saved])
    }

    @Test func updatingAnUnknownMessageThrowsNotFound() async throws {
        let cache = try HermesCache()
        await #expect(throws: OutboxError.self) {
            try await cache.outbox.updateState(.sending, forID: UUID())
        }
    }

    @Test func recordsListByChatOldestFirstAndPruneOnlyAcknowledgedOnes() async throws {
        let cache = try HermesCache()
        let first = record("one", at: 0)
        let second = record("two", at: 5)
        let elsewhere = record("elsewhere", chat: "c2", at: 1)
        for message in [first, second, elsewhere] {
            try await cache.outbox.insert(message)
        }
        #expect(try await cache.outbox.records(inChat: "c1").map(\.text) == ["one", "two"])

        try await cache.outbox.updateState(.sending, forID: first.id)
        try await cache.outbox.updateState(.sent(acknowledgedAt: start), forID: first.id)

        #expect(try await cache.outbox.pruneSent(inChat: "c1") == 1)
        #expect(try await cache.outbox.records(inChat: "c1").map(\.text) == ["two"])
        #expect(try await cache.outbox.records(inChat: "c2").map(\.text) == ["elsewhere"])
    }

    @Test func removingOneMessageKeepsTheOthers() async throws {
        let cache = try HermesCache()
        let kept = record("kept", at: 0)
        let dropped = record("dropped", at: 1)
        try await cache.outbox.insert(kept)
        try await cache.outbox.insert(dropped)

        try await cache.outbox.remove(id: dropped.id, ifCurrently: .pending)

        #expect(try await cache.outbox.records(inChat: "c1") == [kept])
    }

    @Test func messagesKeepTheOrderTheyWereWrittenEvenIfTheClockWentBack() async throws {
        let cache = try HermesCache()
        // Written second, but timed earlier: the queue follows the write order, not the wall clock.
        try await cache.outbox.insert(record("later", at: 5))
        try await cache.outbox.insert(record("earlier", at: 0))

        #expect(try await cache.outbox.records(inChat: "c1").map(\.text) == ["later", "earlier"])
    }

    @Test func aStaleStateChangeIsRefusedAndLeavesTheRowAlone() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        // The send has started. A user's Retry that was tapped on the old, failed row must not move it.
        try await cache.outbox.updateState(.sending, forID: saved.id)

        await #expect(throws: OutboxError.self) {
            try await cache.outbox.updateState(.pending, forID: saved.id, ifCurrently: .failed)
        }

        #expect(try await cache.outbox.records(inChat: "c1").map(\.state.kind) == [.sending])
    }

    @Test func aMessageBeingSentCannotBeRemoved() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        try await cache.outbox.updateState(.sending, forID: saved.id)

        await #expect(throws: OutboxError.self) {
            try await cache.outbox.remove(id: saved.id, ifCurrently: .failed)
        }

        #expect(try await cache.outbox.records(inChat: "c1").count == 1)
    }

    // MARK: - Purge

    @Test func purgingAServerDropsOnlyItsWaitingMessages() async throws {
        let cache = try HermesCache()
        let gone = record("gone", chat: "c1", connection: "removed")
        let kept = record("kept", chat: "c2", connection: "other", at: 1)
        try await cache.outbox.insert(gone)
        try await cache.outbox.insert(kept)

        try await cache.purge(connection: "removed")

        #expect(try await cache.outbox.records(inChat: "c1").isEmpty)
        #expect(try await cache.outbox.records(inChat: "c2") == [kept])
    }

    // MARK: - Migration

    @Test func anExistingDatabaseGainsTheOutboxAndKeepsItsOfflineChatsAsLocalChats() async throws {
        let url = try temporaryDatabaseURL()
        let kept = UUID()
        do {
            // The schema before the outbox existed, with one offline chat in it.
            let older = try DatabaseQueue(path: url.path)
            try HermesCache.migrator.migrate(older, upTo: "offline-chat-v1")
            try await older.write { handle in
                try handle.execute(
                    sql: """
                        INSERT INTO offline_chat (connection, chat_id, session_id, title, created_at, updated_at)
                        VALUES ('x', ?, 's1', 'Kept', ?, ?)
                        """,
                    arguments: [kept.uuidString, start.timeIntervalSince1970, start.timeIntervalSince1970])
            }
        }

        let upgraded = try HermesCache(url: url)
        #expect(try await upgraded.localChats.chat(kept)?.title == "Kept")

        let queued = record("queued after the upgrade")
        try await upgraded.outbox.insert(queued)
        #expect(try await upgraded.outbox.records(inChat: "c1") == [queued])
    }
}
