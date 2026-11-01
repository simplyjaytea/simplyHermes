import Foundation
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
        for message in [second, first, elsewhere] {
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

        try await cache.outbox.remove(id: dropped.id)

        #expect(try await cache.outbox.records(inChat: "c1") == [kept])
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

    @Test func anExistingDatabaseGainsTheOutboxAndKeepsItsOfflineChats() async throws {
        let url = temporaryURL()
        var kept: OfflineChat?
        do {
            // The schema before the outbox existed.
            let older = try HermesCache.openSchema(url: url, upTo: "offline-chat-v1")
            kept = try await older.offlineChats.openChat(
                forSession: "s1", connection: "x", title: "Kept", at: start)
        }

        let upgraded = try HermesCache(url: url)
        #expect(try await upgraded.offlineChats.currentChat(forSession: "s1", connection: "x") == kept)

        let queued = record("queued after the upgrade")
        try await upgraded.outbox.insert(queued)
        #expect(try await upgraded.outbox.records(inChat: "c1") == [queued])
    }
}
