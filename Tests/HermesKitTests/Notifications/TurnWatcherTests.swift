import Foundation
import Testing

@testable import HermesKit

/// Review M1, m1, m2 on #136: notifications come from the chats' real state, use each turn's own reply and outcome,
/// and dedupe on the turn's id.
struct TurnWatcherTests {
    private let chat = NotificationChat(id: "s1", title: "Backup", serverName: "home")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func reply(_ id: String, _ text: String) -> ChatActivity.Reply { .init(id: id, text: text) }

    @Test func aTurnThatStartsAndEndsIsOneEventWithItsOwnReply() {
        var watcher = TurnWatcher()
        let before = ChatActivity(isRunning: false, latestReply: reply("row-1", "old answer"))
        let step1 = watcher.observe(chat, before, now: at(0))
        #expect(step1.isEmpty)
        let step2 = watcher.observe(chat, ChatActivity(isRunning: true, latestReply: before.latestReply), now: at(1))
        #expect(
            step2.isEmpty)
        #expect(watcher.runningFor(chat.key, now: at(26)) == 25)
        let done = ChatActivity(isRunning: false, latestReply: reply("row-2", "new answer"))
        let events = watcher.observe(chat, done, now: at(30))
        #expect(
            events == [
                .turnEnded(
                    chat, turnID: "row-2", startedAt: at(1), endedAt: at(30), outcome: .done,
                    reply: "new answer")
            ])
        let step3 = watcher.observe(chat, done, now: at(31))
        #expect(step3.isEmpty, "seen once")
    }

    /// m1: a turn that fails with no reply says it failed and never shows the previous turn's text.
    @Test func aFailedTurnWithoutAReplyCarriesNoText() {
        var watcher = TurnWatcher()
        let old = reply("row-1", "the previous turn's answer")
        _ = watcher.observe(chat, ChatActivity(isRunning: true, latestReply: old), now: at(0))
        let events = watcher.observe(
            chat, ChatActivity(isRunning: false, latestReply: old, lastTurnFailed: true),
            now: at(5))
        guard case .turnEnded(_, let turnID, _, _, let outcome, let text) = events.first else {
            Issue.record("expected a turn end, got \(events)")
            return
        }
        #expect(outcome == .failed)
        #expect(text.isEmpty)
        #expect(turnID.hasPrefix("s1@"), "no reply: the turn is named by its start")
    }

    @Test func aStoppedTurnIsReportedAsStopped() {
        var watcher = TurnWatcher()
        _ = watcher.observe(chat, ChatActivity(isRunning: true), now: at(0))
        let events = watcher.observe(
            chat, ChatActivity(isRunning: false, latestReply: reply("row-9", "partial")),
            stoppedByUser: true, now: at(2))
        guard case .turnEnded(_, _, _, _, let outcome, _) = events.first else {
            Issue.record("expected a turn end")
            return
        }
        #expect(outcome == .stopped)
    }

    /// m2: the dedupe key is the turn's reply id, so a reconnect that replays the same finished turn notifies once.
    @Test func aReplayedTurnNotifiesOnce() {
        var watcher = TurnWatcher()
        var planner = NotificationPlanner()
        let context = NotificationContext(appIsActive: false, chatOnScreen: nil, multipleServers: false, now: at(10))
        var posted = 0
        for round in 0..<2 {
            let base = Double(round * 100)
            let started = watcher.observe(chat, ChatActivity(isRunning: true), now: at(base))
            let done = ChatActivity(isRunning: false, latestReply: reply("row-7", "hi"))
            let ended = watcher.observe(chat, done, now: at(base + 5))
            for event in started + ended {
                posted += planner.plan(event, context: context, preferences: .init()).count
            }
        }
        #expect(posted == 1)
    }

    @Test func approvalsAppearAndResolve() {
        var watcher = TurnWatcher()
        let waiting = ChatActivity(isRunning: true, approval: .init(id: "r1", command: "rm -rf build"))
        let step4 = watcher.observe(chat, waiting, now: at(0))
        #expect(
            step4 == [
                .approvalWaiting(
                    chat, requestID: "r1",
                    command: "rm -rf build")
            ])
        let step5 = watcher.observe(chat, waiting, now: at(1))
        #expect(step5.isEmpty)
        let next = ChatActivity(isRunning: true, approval: .init(id: "r2", command: "ls"))
        let step6 = watcher.observe(chat, next, now: at(2))
        #expect(
            step6 == [
                .approvalResolved(chat.key, requestID: "r1"),
                .approvalWaiting(chat, requestID: "r2", command: "ls"),
            ])
        let step7 = watcher.observe(chat, ChatActivity(isRunning: true), now: at(3))
        #expect(
            step7 == [
                .approvalResolved(chat.key, requestID: "r2")
            ])
    }

    // MARK: ChatActivity from real state

    @Test func aServerTranscriptGivesItsNewestFinishedReplyAndError() {
        var state = TranscriptState(storedSessionID: "s1")
        state.items = [
            TranscriptItem(id: "u1", content: .user(UserEntry(text: "q", delivery: .sent))),
            TranscriptItem(id: "row-2", content: .assistant(AssistantEntry(text: "answer", isStreaming: false))),
        ]
        let finished = ChatActivity(transcript: state, approval: nil)
        #expect(!finished.isRunning)
        #expect(finished.latestReply == .init(id: "row-2", text: "answer"))
        #expect(!finished.lastTurnFailed)

        state.items.append(
            TranscriptItem(
                id: "row-3", content: .assistant(AssistantEntry(text: "", isStreaming: false, error: "provider down"))))
        #expect(ChatActivity(transcript: state, approval: nil).lastTurnFailed)

        state.items.append(
            TranscriptItem(id: "row-4", content: .assistant(AssistantEntry(text: "…", isStreaming: true))))
        state.turn = TurnActivity()
        let streaming = ChatActivity(transcript: state, approval: nil)
        #expect(streaming.isRunning)
        #expect(streaming.latestReply == nil, "a streaming row is not a finished reply")
    }

    @Test func aLocalSnapshotGivesItsReplyAndFailure() {
        let chatID = UUID()
        let snapshot = LocalChatSnapshot(
            chat: nil,
            messages: [
                LocalChatMessage(chatID: chatID, id: 1, author: .user, text: "q", createdAt: start),
                LocalChatMessage(
                    chatID: chatID, id: 2, author: .assistant(answeredBy: .apple, inReplyTo: 1), text: "a",
                    createdAt: start),
            ],
            isReplying: false, failure: nil, unansweredIDs: [])
        let activity = ChatActivity(local: snapshot)
        #expect(activity.latestReply == .init(id: "local-reply-2", text: "a"))
        #expect(activity.approval == nil)
        var failing = snapshot
        failing.failure = .modelFailed
        #expect(ChatActivity(local: failing).lastTurnFailed)
    }

    // MARK: The in-chat offer

    @Test func theOfferShowsAfterALongTurnThenOnceMoreAfterThreeThenNever() {
        var offer = NotificationOffer()
        let step8 = offer.noteLongTurn(permissionUndecided: false)
        #expect(!step8, "never once iOS has asked")
        let step9 = offer.noteLongTurn(permissionUndecided: true)
        #expect(step9)
        offer.dismiss()
        let step10 = offer.noteLongTurn(permissionUndecided: true)
        #expect(!step10)
        let step11 = offer.noteLongTurn(permissionUndecided: true)
        #expect(!step11)
        let step12 = offer.noteLongTurn(permissionUndecided: true)
        #expect(step12, "back once, after three more long turns")
        offer.dismiss()
        for _ in 0..<10 {
            let step13 = offer.noteLongTurn(permissionUndecided: true)
            #expect(!step13)
        }
    }

    @Test func theOfferStateSurvivesARelaunch() throws {
        let name = "TurnWatcherTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var offer = NotificationOffer.load(from: defaults)
        offer.dismiss()
        _ = offer.noteLongTurn(permissionUndecided: true)
        offer.save(to: defaults)
        #expect(NotificationOffer.load(from: defaults) == offer)
    }
}
