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
            return .deleted(discardedMessages: discarded)
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
        #expect(pauses.isPaused("s1", connection: nil))
        clock.advance(ChatDeleteQueue.window)
        #expect(
            await subject.tick() == [.restored(id: "s1", title: "Trip", reason: "The server refused the delete.")])
        #expect(subject.hiddenIDs.isEmpty, "The chat is back in the list")
        #expect(!pauses.isPaused("s1", connection: nil), "Its waiting messages may go again")
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
        #expect(!pauses.isPaused("s1", connection: nil) && !pauses.isPaused("local-2", connection: nil))
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
            return .deleted(discardedMessages: 0)
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

    private func record(_ text: String, chat: String, connection: String = "x") -> OutboundRecord {
        OutboundRecord(connectionID: connection, chatID: chat, text: text, createdAt: start)
    }

    @Test func aPausedChatSendsNothingAndResumeLetsItGo() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("a", chat: "c1"))
        try await cache.outbox.insert(record("b", chat: "c2"))
        let pauses = OutboxPauses()
        let submitter = CountingSubmitter()
        let paused = OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter, pauses: pauses)
        let other = OutboxDrainer(store: cache.outbox, chatID: "c2", submitter: submitter, pauses: pauses)
        pauses.pause("c1", connection: "x")
        try await paused.drain()
        try await other.drain()
        #expect(await submitter.delivered == ["b"], "Only the paused chat waits")
        #expect(try await cache.outbox.records(inChat: "c1").map(\.state.kind) == [.pending], "Nothing is lost")
        pauses.resume("c1", connection: "x")
        try await paused.drain()
        #expect(await submitter.delivered == ["b", "a"])
    }

    @Test func removeChatPurgesOneServersChatAndCountsWhatWasWaiting() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        let sent = record("sent", chat: "c1")
        let failed = record("failed", chat: "c1")
        let sending = record("sending", chat: "c1")
        for item in [
            sent, failed, sending, record("pending", chat: "c1"), record("other chat", chat: "c2"),
            record("other server", chat: "c1", connection: "y"),
        ] {
            try await store.insert(item)
        }
        try await store.updateState(.sending, forID: sent.id)
        try await store.updateState(.sent(acknowledgedAt: start), forID: sent.id)
        try await store.updateState(.sending, forID: failed.id)
        try await store.updateState(.failed(reason: "no"), forID: failed.id)
        try await store.updateState(.sending, forID: sending.id)
        // m2: only pending and failed count; a message already going out is never promised as discarded.
        #expect(try await store.waitingCount(inChat: "c1", connection: "x") == 2)

        #expect(try await store.removeChat("c1", connection: "x") == 2, "Sent and sending aren't counted")
        // m3: the other server's chat with the same id keeps its message.
        #expect(try await store.records(inChat: "c1").map(\.text) == ["other server"])
        #expect(try await store.records(inChat: "c2").count == 1, "Other chats are untouched")
        #expect(try await store.removeChat("c1", connection: "x") == 0)
        #expect(try await store.waitingCount(inChat: "c1", connection: "y") == 1)
    }

    @Test @MainActor func aCompletedDeletePurgesTheOutboxAndReportsTheCount() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        try await store.insert(record("waiting", chat: "s1"))
        var now = start
        let pauses = OutboxPauses()
        let subject = ChatDeleteQueue(now: { now }, pauses: pauses)
        subject.delete(id: "s1", title: "Trip") {
            .deleted(discardedMessages: try await store.removeChat("s1", connection: "x"))
        }
        // m2: counted after the pause started.
        #expect(pauses.isPaused("s1", connection: nil))
        subject.setWaitingMessages("s1", try await store.waitingCount(inChat: "s1", connection: "x"))
        #expect(subject.latest?.message == "Chat deleted · 1 waiting message discarded")
        #expect(pauses.isPaused("s1", connection: nil))
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
        subject.delete(id: "s1", title: "Trip", waitingMessages: 1) {
            .deleted(discardedMessages: try await store.removeChat("s1", connection: "x"))
        }
        subject.undo("s1")
        now = now.addingTimeInterval(60)
        _ = await subject.tick()
        #expect(try await store.records(inChat: "s1").map(\.text) == ["waiting"], "Never lose a message")
    }

    /// M1: the server delete worked but the purge failed. The chat never comes back, stays paused, and nothing is sent
    /// to it; the tombstone lets the next launch finish the purge.
    @Test @MainActor func aFailedPurgeAfterTheServerDeleteKeepsTheChatGoneAndPaused() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("waiting", chat: "s1"))
        var now = start
        let pauses = OutboxPauses()
        let defaults = UserDefaults(suiteName: "tombstones-\(UUID().uuidString)")!
        let tombstones = OutboxTombstones(defaults: defaults)
        let entry = OutboxTombstones.Entry(connection: "x", chatID: "s1")
        let subject = ChatDeleteQueue(now: { now }, pauses: pauses)
        subject.delete(id: "s1", title: "Trip", connection: "x") {
            // The server delete succeeded (nothing thrown before this point), then the purge fails.
            tombstones.add(entry)
            return .deletedCleanupPending
        }
        now = now.addingTimeInterval(ChatDeleteQueue.window)
        #expect(await subject.tick() == [.deletedCleanupPending(id: "s1")])
        #expect(subject.hiddenIDs == ["s1"], "The row stays hidden; it is not 'back in the list'")
        #expect(pauses.isPaused("s1", connection: "x"), "The pause holds")
        let submitter = CountingSubmitter()
        try await OutboxDrainer(store: cache.outbox, chatID: "s1", submitter: submitter, pauses: pauses).drain()
        #expect(await submitter.delivered.isEmpty, "Nothing is submitted to a deleted chat")
        #expect(tombstones.entries == [entry])
    }

    /// m1: the launch sweep finishes a purge left by a failure or a crash between the server delete and the purge. It
    /// touches only tombstoned chats of that server.
    @Test func theLaunchSweepPurgesOnlyTombstonedChats() async throws {
        let cache = try HermesCache()
        let store = cache.outbox
        for item in [
            record("deleted chat", chat: "s1"), record("live chat", chat: "s2"),
            record("same id, other server", chat: "s1", connection: "y"),
        ] {
            try await store.insert(item)
        }
        let defaults = UserDefaults(suiteName: "tombstones-\(UUID().uuidString)")!
        let tombstones = OutboxTombstones(defaults: defaults)
        tombstones.add(.init(connection: "x", chatID: "s1"))
        // As after a relaunch: a new value over the same defaults.
        let relaunched = OutboxTombstones(defaults: defaults)
        #expect(relaunched.entries.count == 1)
        #expect(await relaunched.sweep(store: store) == 1)
        #expect(try await store.records(inChat: "s1").map(\.text) == ["same id, other server"])
        #expect(try await store.records(inChat: "s2").map(\.text) == ["live chat"], "A live chat is never swept")
        #expect(relaunched.entries.isEmpty)
    }

    @Test func aSweepThatFailsKeepsItsTombstone() async {
        let defaults = UserDefaults(suiteName: "tombstones-\(UUID().uuidString)")!
        let tombstones = OutboxTombstones(defaults: defaults)
        let entry = OutboxTombstones.Entry(connection: "x", chatID: "s1")
        tombstones.add(entry)
        #expect(await tombstones.sweep(store: FailingPurgeStore()) == 0)
        #expect(tombstones.entries == [entry])
    }

    // MARK: Row 99

    /// n2: a pause names its server. Deleting a chat on one server never holds back another server's chat with the
    /// same id (Moss reproduced that with a failed purge: the other chat stayed paused until relaunch).
    @Test @MainActor func aPauseOnOneServerLeavesTheSameChatIDOnAnotherServerSending() async throws {
        let cache = try HermesCache()
        try await cache.outbox.insert(record("to y", chat: "c1", connection: "y"))
        let pauses = OutboxPauses()
        let subject = ChatDeleteQueue(now: { start }, pauses: pauses)
        subject.delete(id: "c1", title: "Same id", connection: "x") { .deletedCleanupPending }
        #expect(pauses.isPaused("c1", connection: "x"))
        #expect(!pauses.isPaused("c1", connection: "y"))

        let submitter = CountingSubmitter()
        try await OutboxDrainer(store: cache.outbox, chatID: "c1", submitter: submitter, pauses: pauses).drain()
        #expect(await submitter.delivered == ["to y"], "server y's chat c1 still sends while x's c1 is deleted")
        subject.undo("c1")
        #expect(!pauses.isPaused("c1", connection: "x"), "Undo resumes the same server's pause")
    }

    @Test func pausesAreKeptPerServerAndPerChat() {
        let pauses = OutboxPauses()
        pauses.pause("c1", connection: "x")
        #expect(pauses.isPaused("c1", connection: "x"))
        #expect(!pauses.isPaused("c1", connection: "y"))
        #expect(!pauses.isPaused("c1", connection: nil))
        #expect(!pauses.isPaused("c2", connection: "x"))
        pauses.resume("c1", connection: "y")
        #expect(pauses.isPaused("c1", connection: "x"), "resuming another server changes nothing")
        pauses.resume("c1", connection: "x")
        #expect(!pauses.isPaused("c1", connection: "x"))
    }

    /// n1: the server delete, tombstone and purge as one HermesKit step.
    @Test func serverDeleteThenPurgeRemovesTheTombstone() async throws {
        let tombstones = freshTombstones()
        var purges = 0
        let result = try await ServerChatDelete.commit(
            chatID: "s1", connection: "x", tombstones: tombstones, deleteOnServer: {},
            purge: {
                purges += 1
                return 2
            })
        #expect(result == .deleted(discardedMessages: 2))
        #expect(purges == 1)
        #expect(tombstones.entries.isEmpty)
    }

    @Test func aPurgeThatFailsOnceIsTriedAgain() async throws {
        let tombstones = freshTombstones()
        var purges = 0
        let result = try await ServerChatDelete.commit(
            chatID: "s1", connection: "x", tombstones: tombstones, deleteOnServer: {},
            purge: {
                purges += 1
                if purges == 1 { throw ServerRefused() }
                return 1
            })
        #expect(result == .deleted(discardedMessages: 1))
        #expect(purges == 2)
        #expect(tombstones.entries.isEmpty)
    }

    @Test func aPurgeThatFailsTwiceLeavesTheTombstoneForTheLaunchSweep() async throws {
        let tombstones = freshTombstones()
        var purges = 0
        let result = try await ServerChatDelete.commit(
            chatID: "s1", connection: "x", tombstones: tombstones, deleteOnServer: {},
            purge: {
                purges += 1
                throw ServerRefused()
            })
        #expect(result == .deletedCleanupPending)
        #expect(purges == 2)
        #expect(tombstones.entries == [OutboxTombstones.Entry(connection: "x", chatID: "s1")])
    }

    @Test func aFailedServerDeleteTombstonesAndPurgesNothing() async {
        let tombstones = freshTombstones()
        var purges = 0
        await #expect(throws: ServerRefused.self) {
            _ = try await ServerChatDelete.commit(
                chatID: "s1", connection: "x", tombstones: tombstones, deleteOnServer: { throw ServerRefused() },
                purge: {
                    purges += 1
                    return 0
                })
        }
        #expect(purges == 0, "the chat still exists, so its messages stay")
        #expect(tombstones.entries.isEmpty)
    }

    private func freshTombstones() -> OutboxTombstones {
        let name = "ChatDeleteQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return OutboxTombstones(defaults: defaults)
    }

}

/// An outbox whose purge always fails, for the sweep's failure path.
private struct FailingPurgeStore: OutboxStore {
    struct Failed: Error {}
    func insert(_ record: OutboundRecord) async throws { throw Failed() }
    func updateState(_ state: DeliveryState, forID id: UUID) async throws -> OutboundRecord { throw Failed() }
    func updateState(
        _ state: DeliveryState, forID id: UUID, ifCurrently current: DeliveryKind
    ) async throws -> OutboundRecord { throw Failed() }
    func records(inChat chatID: String) async throws -> [OutboundRecord] { [] }
    func pruneSent(inChat chatID: String) async throws -> Int { 0 }
    func remove(id: UUID, ifCurrently current: DeliveryKind) async throws { throw Failed() }
    func removeChat(_ chatID: String, connection: String) async throws -> Int { throw Failed() }
}
