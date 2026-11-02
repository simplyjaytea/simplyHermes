import Foundation
import Testing

@testable import HermesKit

/// Counts deliveries, acknowledging each one.
private actor CountingSubmitter: OutboxSubmitter {
    private(set) var delivered: [String] = []

    func deliver(_ record: OutboundRecord) async -> SubmitOutcome {
        delivered.append(record.text)
        return .acknowledged
    }
}

private struct ServerRefused: LocalizedError {
    var errorDescription: String? { "The server refused the delete." }
}

/// Undo for chat delete (feature C): the Undo window, Undo, expiry, failure and background cancel, plus the outbox
/// pause and purge. The clock is injected and `tick()` is driven by hand.
@MainActor
struct ChatDeleteQueueTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// Records which chats were deleted for real.
    private final class Log {
        var deleted: [String] = []
    }

    private func queue(_ clock: Clock, _ pauses: OutboxPauses = OutboxPauses()) -> ChatDeleteQueue {
        ChatDeleteQueue(now: { clock.now }, pauses: pauses)
    }

    private func commit(_ id: String, _ log: Log, discarded: Int = 0) -> ChatDeleteQueue.Commit {
        {
            log.deleted.append(id)
            return discarded
        }
    }

    @Test func deleteHidesTheChatButDeletesNothingYet() async {
        let clock = Clock()
        let log = Log()
        let subject = queue(clock)
        subject.delete(id: "s1", title: "Trip", commit: commit("s1", log))
        #expect(subject.hiddenIDs == ["s1"])
        #expect(subject.latest?.message == "Chat deleted")
        #expect(subject.latest?.announcement == "Chat deleted. Undo available.")
        clock.advance(ChatDeleteQueue.window - 0.1)
        #expect(await subject.tick().isEmpty)
        #expect(log.deleted.isEmpty)
    }

    @Test func theDeleteRunsWhenTheWindowEnds() async {
        let clock = Clock()
        let log = Log()
        let subject = queue(clock)
        subject.delete(id: "s1", title: "Trip", commit: commit("s1", log))
        clock.advance(ChatDeleteQueue.window)
        #expect(await subject.tick() == [.deleted(id: "s1", discardedMessages: 0)])
        #expect(log.deleted == ["s1"])
        #expect(subject.hiddenIDs.isEmpty)
        #expect(subject.latest == nil)
        #expect(await subject.tick().isEmpty, "A delete runs once")
    }

    @Test func undoBringsTheChatBackAndNothingIsDeleted() async {
        let clock = Clock()
        let log = Log()
        let subject = queue(clock)
        subject.delete(id: "s1", title: "Trip", commit: commit("s1", log))
        #expect(subject.undo("s1"))
        #expect(subject.hiddenIDs.isEmpty)
        clock.advance(60)
        #expect(await subject.tick().isEmpty)
        #expect(log.deleted.isEmpty)
        #expect(!subject.undo("s1"), "Undo after the fact does nothing")
    }

    @Test func twoDeletesInARowEachKeepTheirOwnWindow() async {
        let clock = Clock()
        let log = Log()
        let subject = queue(clock)
        subject.delete(id: "s1", title: "One", commit: commit("s1", log))
        clock.advance(2)
        subject.delete(id: "local-2", title: "Two", commit: commit("local-2", log))
        #expect(subject.latest?.id == "local-2", "The toast offers the newest")
        #expect(subject.hiddenIDs == ["s1", "local-2"])
        clock.advance(3)
        #expect(await subject.tick() == [.deleted(id: "s1", discardedMessages: 0)])
        #expect(subject.hiddenIDs == ["local-2"])
        // Undo on the toast still reaches the second chat.
        #expect(subject.undo("local-2"))
        clock.advance(10)
        #expect(await subject.tick().isEmpty)
        #expect(log.deleted == ["s1"])
    }

    @Test func deletingAChatAlreadyPendingIsIgnored() {
        let subject = queue(Clock())
        let log = Log()
        #expect(subject.delete(id: "s1", title: "Trip", commit: commit("s1", log)) != nil)
        #expect(subject.delete(id: "s1", title: "Trip", commit: commit("s1", log)) == nil)
        #expect(subject.pending.count == 1)
    }

    @Test func aFailedServerDeleteBringsTheChatBackWithTheReason() async {
        let clock = Clock()
        let pauses = OutboxPauses()
        let subject = queue(clock, pauses)
        subject.delete(id: "s1", title: "Trip") { throw ServerRefused() }
        #expect(pauses.isPaused("s1"))
        clock.advance(ChatDeleteQueue.window)
        #expect(
            await subject.tick() == [.restored(id: "s1", title: "Trip", reason: "The server refused the delete.")])
        #expect(subject.hiddenIDs.isEmpty, "The chat is back in the list")
        #expect(!pauses.isPaused("s1"), "Its waiting messages may go again")
    }

    @Test func leavingTheForegroundCancelsEveryPendingDelete() async {
        let clock = Clock()
        let log = Log()
        let pauses = OutboxPauses()
        let subject = queue(clock, pauses)
        subject.delete(id: "s1", title: "One", commit: commit("s1", log))
        subject.delete(id: "local-2", title: "Two", commit: commit("local-2", log))
        #expect(subject.cancelAll().map(\.id) == ["s1", "local-2"])
        #expect(subject.hiddenIDs.isEmpty)
        #expect(!pauses.isPaused("s1") && !pauses.isPaused("local-2"))
        clock.advance(60)
        #expect(await subject.tick().isEmpty)
        #expect(log.deleted.isEmpty)
    }

    @Test func voiceOverFocusHoldsTheToastAndReleaseRestartsTheWindow() async {
        let clock = Clock()
        let log = Log()
        let subject = queue(clock)
        subject.delete(id: "s1", title: "Trip", commit: commit("s1", log))
        subject.hold("s1", true)
        clock.advance(60)
        #expect(await subject.tick().isEmpty, "Held while VoiceOver is on the toast")
        #expect(subject.nextDeadline == nil)
        subject.hold("s1", false)
        clock.advance(ChatDeleteQueue.window - 1)
        #expect(await subject.tick().isEmpty, "A full window starts again on release")
        clock.advance(1)
        #expect(await subject.tick() == [.deleted(id: "s1", discardedMessages: 0)])
    }

    @Test func theToastCountsWaitingMessages() {
        let subject = queue(Clock())
        let log = Log()
        subject.delete(id: "s1", title: "A", waitingMessages: 1, commit: commit("s1", log))
        #expect(subject.latest?.message == "Chat deleted · 1 waiting message discarded")
        #expect(subject.latest?.announcement == "Chat deleted. 1 waiting message discarded. Undo available.")
        subject.delete(id: "s2", title: "B", waitingMessages: 3, commit: commit("s2", log))
        #expect(subject.latest?.message == "Chat deleted · 3 waiting messages discarded")
    }

    @Test func aChatStaysHiddenWhileItsDeleteRuns() async {
        let clock = Clock()
        let subject = queue(clock)
        var seenWhileRunning: Set<String> = []
        subject.delete(id: "s1", title: "Trip") {
            seenWhileRunning = subject.hiddenIDs
            return 0
        }
        clock.advance(ChatDeleteQueue.window)
        _ = await subject.tick()
        #expect(seenWhileRunning == ["s1"], "A refresh during the delete doesn't bring the row back")
    }
}

/// The outbox side of feature C: a pending delete pauses the chat's sends, and the real delete purges its messages in
/// one write and reports how many were waiting.
struct ChatDeleteOutboxTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ text: String, chat: String) -> OutboundRecord {
        OutboundRecord(connectionID: "x", chatID: chat, text: text, createdAt: start)
    }

    @Test func aPausedChatSendsNothingAndResumeLetsItGo() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("a", chat: "c1"))
        try await cache.outbox.insert(record("b", chat: "c2"))
        let pauses = OutboxPauses()
        let submitter = CountingSubmitter()
        let paused = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter, pauses: pauses)
        let other = OutboxDrainer(store: cache.outbox, chatID: "c2", submitter: submitter, pauses: pauses)
        pauses.pause("c1")
        try await paused.drain()
        try await other.drain()
        #expect(await submitter.delivered == ["b"], "Only the paused chat waits")
        #expect(try await cache.outbox.records(inChat: "c1").map(\.state.kind) == [.pending], "Nothing is lost")
        pauses.resume("c1")
        try await paused.drain()
        #expect(await submitter.delivered == ["b", "a"])
    }

    @Test func removeChatPurgesOneChatAndCountsWhatWasWaiting() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        let sent = record("sent", chat: "c1")
        let failed = record("failed", chat: "c1")
        for item in [sent, failed, record("pending", chat: "c1"), record("other", chat: "c2")] {
            try await store.insert(item)
        }
        try await store.updateState(.sending, forID: sent.id)
        try await store.updateState(.sent(acknowledgedAt: start), forID: sent.id)
        try await store.updateState(.sending, forID: failed.id)
        try await store.updateState(.failed(reason: "no"), forID: failed.id)
        #expect(try await store.waitingCount(inChat: "c1") == 2)

        #expect(try await store.removeChat("c1") == 2, "The sent message isn't counted as discarded")
        #expect(try await store.records(inChat: "c1").isEmpty)
        #expect(try await store.records(inChat: "c2").count == 1, "Other chats are untouched")
        #expect(try await store.removeChat("c1") == 0)
    }

    @Test @MainActor func aCompletedDeletePurgesTheOutboxAndReportsTheCount() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        try await store.insert(record("waiting", chat: "s1"))
        var now = start
        let pauses = OutboxPauses()
        let subject = ChatDeleteQueue(now: { now }, pauses: pauses)
        let waiting = try await store.waitingCount(inChat: "s1")
        subject.delete(id: "s1", title: "Trip", waitingMessages: waiting) { try await store.removeChat("s1") }
        #expect(subject.latest?.message == "Chat deleted · 1 waiting message discarded")
        #expect(pauses.isPaused("s1"))
        now = now.addingTimeInterval(ChatDeleteQueue.window)
        #expect(await subject.tick() == [.deleted(id: "s1", discardedMessages: 1)])
        #expect(try await store.records(inChat: "s1").isEmpty)
    }

    @Test @MainActor func undoKeepsTheWaitingMessage() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        try await store.insert(record("waiting", chat: "s1"))
        var now = start
        let subject = ChatDeleteQueue(now: { now }, pauses: OutboxPauses())
        subject.delete(id: "s1", title: "Trip", waitingMessages: 1) { try await store.removeChat("s1") }
        subject.undo("s1")
        now = now.addingTimeInterval(60)
        _ = await subject.tick()
        #expect(try await store.records(inChat: "s1").map(\.text) == ["waiting"], "Never lose a message")
    }
}
