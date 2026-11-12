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
        OutboundRecord(
            connectionID: "x", chatID: chat, text: text, createdAt: start.addingTimeInterval(Double(text.count)))
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

    @Test func aFailedMessageIsKeptAsFailedAndStopsThePass() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter([.failed("Can't reach the server")])
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        try await drainer.drain()
        // A later drain does not resend it on its own: only Retry does.
        try await drainer.drain()

        #expect(await submitter.delivered == ["a"])
        #expect(try await states(cache) == ["a:failed", "b:pending"])
        let failed = try await cache.outbox.records(inChat: "c1").first
        #expect(failed?.state == .failed(reason: "Can't reach the server"))
    }

    @Test func aRetriedMessageGoesOutAndTheWaitingOnesFollow() async throws {
        let cache = try HermesCache()
        let first = record("a")
        try await cache.outbox.insert(first)
        try await cache.outbox.insert(record("b"))
        let submitter = ScriptedSubmitter([.failed("boom")])
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)
        try await drainer.drain()

        try await drainer.retry(first.id)

        #expect(await submitter.delivered == ["a", "a", "b"])
        #expect(try await states(cache) == ["a:sent", "b:sent"])
    }

    @Test func aRetryThatRacesASendInFlightIsRefusedAndTheMessageIsSentOnce() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        await submitter.block(true)
        let inFlight = Task { try await drainer.drain() }
        while await submitter.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }

        // A second tap on Retry while `a` is still in flight must change nothing.
        await #expect(throws: OutboxError.self) { try await drainer.retry(saved.id) }

        await submitter.block(false)
        try await inFlight.value
        #expect(await submitter.delivered == ["a"])
        #expect(try await states(cache) == ["a:sent"])
    }

    @Test func aCancelledDrainSendsNothingMoreAfterTheMessageInFlight() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        await submitter.block(true)
        let pass = Task { try await drainer.drain() }
        while await submitter.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
        // The chat is closed while `a` is in flight. `a` finishes, and `b` is not sent.
        pass.cancel()
        await submitter.block(false)
        try await pass.value

        #expect(await submitter.delivered == ["a"])
        #expect(try await states(cache) == ["a:sent", "b:pending"])
    }

    @Test func aStuckSendHoldsBackTheMessagesAfterIt() async throws {
        let cache = try HermesCache()
        let stuck = record("a")
        try await cache.outbox.insert(stuck)
        try await cache.outbox.insert(record("b"))
        // The app stopped mid-send, and no attach has recovered the message yet.
        try await cache.outbox.updateState(.sending, forID: stuck.id)
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter)

        try await drainer.drain()

        #expect(await submitter.delivered.isEmpty)
        #expect(try await states(cache) == ["a:sending", "b:pending"])
    }

    @Test func retryOnlyAppliesToAFailedMessage() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: ScriptedSubmitter())
        await #expect(throws: OutboxError.self) { try await drainer.retry(saved.id) }
        #expect(try await states(cache) == ["a:pending"])
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

    // Try again can reattach a chat while one of its messages is in flight on the old controller. The chat keeps one
    // drainer for its life and points it at the new controller, so the message goes out once (PR #113 review, M1).

    @Test func swappingTheSubmitterWhileAMessageIsInFlightSendsItOnce() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let old = ScriptedSubmitter()
        let new = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: old)

        await old.block(true)
        let firstPass = Task { try await drainer.drain() }
        while await old.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }

        // The chat reattaches on a new controller while `a` is still in flight on the old one.
        await drainer.use(new)
        try await drainer.drain()
        #expect(await new.delivered.isEmpty)

        await old.block(false)
        try await firstPass.value

        #expect(await old.delivered == ["a"])
        #expect(await new.delivered == ["b"])
        #expect(try await states(cache) == ["a:sent", "b:sent"])
    }

    // A chat model is rebuilt when the user switches servers and back. The rebuilt model attaches the way
    // `LiveChatModel.connectAndFollow()` does: it takes the chat's drainer from the process-wide `OutboxDrainers`,
    // recovers only when the drainer is new, and otherwise swaps in its controller (board row 121).

    /// One attach, as the chat model does it.
    private func attach(
        _ drainers: OutboxDrainers, store: any OutboxStore, submitter: any OutboxSubmitter,
        onChange: @escaping @Sendable () async -> Void = {}
    ) async throws -> OutboxDrainer {
        let (drainer, isNew) = drainers.drainer(forChat: "c1") {
            OutboxDrainer(store: store, chatID: "c1", submitter: submitter, onChange: onChange)
        }
        if isNew {
            try await drainer.recoverInterrupted()
        } else {
            await drainer.use(submitter, onChange: onChange)
        }
        return drainer
    }

    @Test func aRebuiltChatModelDoesNotResendAMessageInFlightOnTheOldOne() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let drainers = OutboxDrainers()
        let old = ScriptedSubmitter()
        let new = ScriptedSubmitter()

        // The first model attaches and starts sending `a`, which stays in flight.
        let first = try await attach(drainers, store: cache.outbox, submitter: old)
        await old.block(true)
        let firstPass = Task { try await first.drain() }
        while await old.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }

        // Server switch away and back: the old model is dropped, a new one attaches to the same chat and drains.
        let second = try await attach(drainers, store: cache.outbox, submitter: new)
        #expect(second === first, "Every model of a chat shares its drainer")
        try await second.drain()
        #expect(await new.delivered.isEmpty, "`a` is still in flight; nothing goes out beside it")

        await old.block(false)
        try await firstPass.value
        try await second.drain()

        #expect(await old.delivered == ["a"])
        #expect(await new.delivered == ["b"])
        #expect(try await states(cache) == ["a:sent", "b:sent"])
    }

    @Test func theNewestModelIsTheOneThatHearsAboutChanges() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("a"))
        let drainers = OutboxDrainers()
        let firstScreen = Counter()
        let secondScreen = Counter()
        _ = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), onChange: { await firstScreen.bump() })
        let drainer = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), onChange: { await secondScreen.bump() })

        try await drainer.drain()

        #expect(await firstScreen.count == 0)
        #expect(await secondScreen.count > 0)
    }

    @Test func eachChatHasItsOwnDrainerAndOnlyItsFirstAttachIsNew() throws {
        let drainers = OutboxDrainers()
        let store = try HermesCache().outbox
        let make = { (chat: String) in
            drainers.drainer(forChat: chat) {
                OutboxDrainer(store: store, chatID: chat, submitter: ScriptedSubmitter())
            }
        }
        let first = make("c1")
        let second = make("c2")
        let firstAgain = make("c1")
        #expect(first.isNew && second.isNew)
        #expect(!firstAgain.isNew)
        #expect(firstAgain.drainer === first.drainer)
        #expect(second.drainer !== first.drainer)
    }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
