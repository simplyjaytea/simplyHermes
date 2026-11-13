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
        let drainer = OutboxDrainer(
            store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter, clock: { self.start })

        try await drainer.drain()
        try await drainer.drain()

        #expect(await submitter.delivered == ["a", "b", "c"])
        #expect(try await states(cache) == ["a:sent", "b:sent", "c:sent"])
    }

    @Test func deferredMessageStaysPendingAndTheRestWait() async throws {
        let cache = try HermesCache()
        for text in ["a", "b", "c"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter([.acknowledged, .deferred])
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)
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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

        try await drainer.drain()

        #expect(await submitter.delivered.isEmpty)
        #expect(try await states(cache) == ["a:sending", "b:pending"])
    }

    @Test func retryOnlyAppliesToAFailedMessage() async throws {
        let cache = try HermesCache()
        let saved = record("a")
        try await cache.outbox.insert(saved)
        let drainer = OutboxDrainer(
            store: cache.outbox, chatID: "c1", connectionID: "x", submitter: ScriptedSubmitter())
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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: relaunched.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

        try await drainer.recoverInterrupted()
        try await drainer.drain()

        #expect(await submitter.delivered == ["kept"])
        #expect(try await states(relaunched) == ["kept:sent"])
    }

    @Test func aDrainRequestedDuringAPassIsFoldedIntoIt() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)

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
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: old)

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
        owner: UUID = UUID(), onChange: @escaping @Sendable () async -> Void = {}
    ) async throws -> OutboxDrainer {
        let (drainer, isNew) = drainers.drainer(forChat: "c1", connection: "x") {
            OutboxDrainer(store: store, chatID: "c1", connectionID: "x", submitter: submitter)
        }
        await drainer.observe(owner: owner, onChange)
        if isNew {
            try await drainer.recoverInterrupted()
        } else {
            await drainer.use(submitter)
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

    // #133 leftover: a chat open in two windows. Both screens refresh, not only the newest model's.
    @Test func everyOpenCopyOfAChatHearsAboutChanges() async throws {
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

        #expect(await firstScreen.count > 0)
        #expect(await secondScreen.count > 0)
    }

    @Test func aModelThatStopsObservingNoLongerHearsAndTheOtherStillDoes() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("a"))
        let drainers = OutboxDrainers()
        let closed = UUID()
        let closedScreen = Counter()
        let openScreen = Counter()
        _ = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), owner: closed,
            onChange: { await closedScreen.bump() })
        let drainer = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), onChange: { await openScreen.bump() })

        await drainer.stopObserving(owner: closed)
        try await drainer.drain()

        #expect(await closedScreen.count == 0)
        #expect(await openScreen.count > 0)
    }

    @Test func aModelThatReattachesHearsOnceNotTwice() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("a"))
        let drainers = OutboxDrainers()
        let owner = UUID()
        let screen = Counter()
        _ = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), owner: owner,
            onChange: { await screen.bump() })
        // Try again reattaches the same model: the same owner, a new controller.
        let drainer = try await attach(
            drainers, store: cache.outbox, submitter: ScriptedSubmitter(), owner: owner,
            onChange: { await screen.bump() })

        try await drainer.drain()

        // One pending message makes two writes (sending, sent). Twice the callbacks would mean 4.
        #expect(await screen.count == 2)
    }

    // #133 leftover: the registry forgets a chat that was deleted.
    @Test func aDeletedChatsDrainerIsForgottenAndOnlyThatOne() throws {
        let drainers = OutboxDrainers()
        let store = try HermesCache().outbox
        func make(_ chat: String, _ connection: String) -> Bool {
            drainers.drainer(forChat: chat, connection: connection) {
                OutboxDrainer(store: store, chatID: chat, connectionID: connection, submitter: ScriptedSubmitter())
            }.isNew
        }
        #expect(make("c1", "A") && make("c1", "B") && make("c2", "A"))
        #expect(drainers.forget(chat: "c1", connection: "A"))
        #expect(!drainers.forget(chat: "c1", connection: "A"))
        #expect(make("c1", "A"), "A deleted chat's drainer is new if the id is ever used again")
        #expect(!make("c1", "B"), "The same chat id on another server keeps its drainer")
        #expect(!make("c2", "A"))
    }

    @Test func aRemovedServersDrainersAreAllForgotten() throws {
        let drainers = OutboxDrainers()
        let store = try HermesCache().outbox
        for (chat, connection) in [("c1", "A"), ("c2", "A"), ("c1", "B")] {
            _ = drainers.drainer(forChat: chat, connection: connection) {
                OutboxDrainer(store: store, chatID: chat, connectionID: connection, submitter: ScriptedSubmitter())
            }
        }
        #expect(drainers.forgetAll(connection: "A") == 2)
        #expect(drainers.forgetAll(connection: "A") == 0)
        #expect(!drainers.forget(chat: "c1", connection: "A"))
        #expect(drainers.forget(chat: "c1", connection: "B"))
    }

    @Test func eachChatHasItsOwnDrainerAndOnlyItsFirstAttachIsNew() throws {
        let drainers = OutboxDrainers()
        let store = try HermesCache().outbox
        let make = { (chat: String) in
            drainers.drainer(forChat: chat, connection: "x") {
                OutboxDrainer(store: store, chatID: chat, connectionID: "x", submitter: ScriptedSubmitter())
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

extension OutboxDrainerTests {
    // Two servers can have a chat with the same id: the same Hermes saved under two addresses shares every id, and
    // independent servers can collide. A message must only ever go out through the server it was written for.

    @Test func aDrainerSendsOnlyItsOwnServersMessages() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(
            OutboundRecord(connectionID: "server-A", chatID: "c1", text: "for A", createdAt: start))
        try await cache.outbox.insert(
            OutboundRecord(
                connectionID: "server-B", chatID: "c1", text: "for B", createdAt: start.addingTimeInterval(1)))
        let serverB = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "server-B", submitter: serverB)

        try await drainer.drain()

        #expect(await serverB.delivered == ["for B"], "Server A's message never goes out through server B")
        let states = try await cache.outbox.records(inChat: "c1").map { "\($0.connectionID):\($0.state.kind)" }
        #expect(states.sorted() == ["server-A:pending", "server-B:sent"])
    }

    @Test func anotherServersFailedMessageDoesNotHoldThisServerBack() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(
            OutboundRecord(connectionID: "server-A", chatID: "c1", text: "A failed", createdAt: start))
        _ = try await cache.outbox.updateState(
            .failed(reason: "refused"), forID: try #require(try await cache.outbox.records(inChat: "c1").first?.id))
        try await cache.outbox.insert(
            OutboundRecord(
                connectionID: "server-B", chatID: "c1", text: "for B", createdAt: start.addingTimeInterval(1)))
        let serverB = ScriptedSubmitter()

        try await OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "server-B", submitter: serverB).drain()

        #expect(await serverB.delivered == ["for B"])
    }

    @Test func recoveryResetsOnlyItsOwnServersMessages() async throws {
        let cache = try HermesCache()
        for (server, text) in [("server-A", "A in flight"), ("server-B", "B in flight")] {
            let record = OutboundRecord(connectionID: server, chatID: "c1", text: text, createdAt: start)
            try await cache.outbox.insert(record)
            _ = try await cache.outbox.updateState(.sending, forID: record.id)
        }
        let drainer = OutboxDrainer(
            store: cache.outbox, chatID: "c1", connectionID: "server-B", submitter: ScriptedSubmitter())

        try await drainer.recoverInterrupted()

        let states = try await cache.outbox.records(inChat: "c1").map { "\($0.connectionID):\($0.state.kind)" }
        #expect(states.sorted() == ["server-A:sending", "server-B:pending"], "A's message may still be in flight on A")
    }

    /// Dinesh's #133 review, M1: the old model's drain is cancelled while `a` is in flight, and the rebuilt model asks
    /// for a drain. Its request folds into the cancelled pass, which must still send `b`.
    @Test func aDrainAskedForDuringACancelledPassStillSendsTheNextMessage() async throws {
        let cache = try HermesCache()
        for text in ["a", "b"] { try await cache.outbox.insert(record(text)) }
        let submitter = ScriptedSubmitter()
        let drainer = OutboxDrainer(store: cache.outbox, chatID: "c1", connectionID: "x", submitter: submitter)
        await submitter.block(true)
        let oldModel = Task { try await drainer.drain() }
        while await submitter.delivered.isEmpty { try await Task.sleep(for: .milliseconds(2)) }

        oldModel.cancel()
        try await drainer.drain()
        await submitter.block(false)
        try await oldModel.value

        #expect(await submitter.delivered == ["a", "b"])
        #expect(try await states(cache) == ["a:sent", "b:sent"])
    }

    @Test func theSameChatIdOnTwoServersGetsTwoDrainers() throws {
        let drainers = OutboxDrainers()
        let store = try HermesCache().outbox
        let make = { (server: String) in
            drainers.drainer(forChat: "c1", connection: server) {
                OutboxDrainer(store: store, chatID: "c1", connectionID: server, submitter: ScriptedSubmitter())
            }
        }
        let onA = make("server-A")
        let onB = make("server-B")
        #expect(onA.isNew && onB.isNew, "Each server's first attach recovers its own messages")
        #expect(onA.drainer !== onB.drainer)
    }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
