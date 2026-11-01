import Foundation
import Testing

@testable import HermesKit

/// Answers deliveries from a script (acknowledging once the script runs out) and records what it was asked to send.
private actor ScriptedSubmitter: OutboxSubmitter {
    private var script: [SubmitOutcome]
    private(set) var delivered: [String] = []
    /// While true, a delivery waits. Tests use it to overlap two drains.
    private(set) var blocking = false

    init(_ script: [SubmitOutcome] = []) {
        self.script = script
    }

    func block(_ enabled: Bool) { blocking = enabled }

    func deliver(_ record: OutboundRecord) async -> SubmitOutcome {
        delivered.append(record.text)
        while blocking { try? await Task.sleep(for: .milliseconds(2)) }
        return script.isEmpty ? .acknowledged : script.removeFirst()
    }
}

struct OutboxDrainerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ text: String, chat: String = "c1") -> OutboundRecord {
        OutboundRecord(chatID: chat, text: text, createdAt: start.addingTimeInterval(Double(text.count)))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("drainer-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
    }

    private func states(_ cache: HermesCache, chat: String = "c1") async throws -> [String] {
        try await cache.outbox.records(inChat: chat).map { "\($0.text):\($0.state.kind)" }
    }

    @Test func pendingMessagesGoOutInOrderOnceEach() async throws {
        let cache = try HermesCache()
        for text in ["a", "b", "c"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter, clock: { self.start })

        try await drainer.drain()
        try await drainer.drain()

        #expect(await submitter.delivered == ["a", "b", "c"])
        #expect(try await states(cache) == ["a:sent", "b:sent", "c:sent"])
    }

    @Test func deferredMessageStaysPendingAndTheRestWait() async throws {
        let cache = try HermesCache()
        for text in ["a", "b", "c"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter([.acknowledged, .deferred])
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        try await drainer.drain()
        #expect(try await states(cache) == ["a:sent", "b:pending", "c:pending"])

        // The next drain sends b, then c. Each goes out exactly once more.
        try await drainer.drain()
        #expect(await submitter.delivered == ["a", "b", "b", "c"])
        #expect(try await states(cache) == ["a:sent", "b:sent", "c:sent"])
    }

    @Test func aFailedMessageStaysPendingAndStopsThePass() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter([.failed("Can't reach the server")])
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        try await drainer.drain()

        #expect(await submitter.delivered == ["a"])
        #expect(try await states(cache) == ["a:pending", "b:pending"])
    }

    @Test func aMessageInterruptedMidSendReturnsToPendingOnAttach() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        // The app was killed while the message was `sending`.
        try await cache.outbox.updateState(.sending, forID: saved.id)
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        try await drainer.recoverInterrupted()
        #expect(try await states(cache) == ["a:pending"])

        try await drainer.drain()
        #expect(await submitter.delivered == ["a"])
        #expect(try await states(cache) == ["a:sent"])
    }

    @Test func aPendingMessageSurvivesARelaunchAndGoesOutOnce() async throws {
        let url = temporaryURL()
        do {
            let cache = try HermesCache(url: url)
            try await cache.outbox.insert(record("kept"))
        }
        let relaunched = try HermesCache(url: url)
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: relaunched.outbox, chatID: "c1", submitter: submitter)

        try await drainer.recoverInterrupted()
        try await drainer.drain()

        #expect(await submitter.delivered == ["kept"])
        #expect(try await states(relaunched) == ["kept:sent"])
    }

    @Test func aDrainRequestedDuringAPassIsFoldedIntoIt() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        await submitter.block(true)
        let first = Task { try await drainer.drain() }
        while await submitter.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }

        // A second drain while `a` is in flight returns at once and sends nothing of its own.
        try await drainer.drain()
        #expect(await submitter.delivered == ["a"])

        await submitter.block(false)
        try await first.value
        #expect(await submitter.delivered == ["a", "b"])
        #expect(try await states(cache) == ["a:sent", "b:sent"])
    }
}
