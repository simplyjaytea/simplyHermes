import Foundation
import Testing

@testable import HermesKit

/// Moss's FAIL on #136: two saved servers can have a chat with the same id. Notifications are keyed by server and
/// chat, as the outbox is since #133: ids, threads, the "never twice" record, removal of an answered approval, the
/// chat on screen, the watcher's state and the tap link.
struct NotificationServerScopeTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let onA = NotificationChat(id: "c1", title: "On A", serverName: "alpha", connection: "A")
    private let onB = NotificationChat(id: "c1", title: "On B", serverName: "beta", connection: "B")

    private func context(onScreen: NotificationChatKey? = nil, active: Bool = false) -> NotificationContext {
        NotificationContext(
            appIsActive: active, chatOnScreen: onScreen, multipleServers: true, now: start.addingTimeInterval(60))
    }

    private func ended(_ chat: NotificationChat, turn: String = "row-7") -> NotificationEvent {
        .turnEnded(
            chat, turnID: turn, startedAt: start, endedAt: start.addingTimeInterval(30), outcome: .done, reply: "hi")
    }

    private func posts(_ actions: [NotificationAction]) -> [NotificationRequest] {
        actions.compactMap { if case .post(let request) = $0 { request } else { nil } }
    }

    @Test func repliesOnTwoServersWithTheSameChatIDAreTwoNotifications() {
        var planner = NotificationPlanner()
        let fromA = posts(planner.plan(ended(onA), context: context(), preferences: .init()))
        // The same turn id too: B's reply must not count as A's "already told".
        let fromB = posts(planner.plan(ended(onB), context: context(), preferences: .init()))
        #expect(fromA.count == 1)
        #expect(fromB.count == 1, "B's reply is not swallowed by A's never-twice record")
        #expect(fromA.first?.id != fromB.first?.id, "B's notification does not replace A's")
        #expect(fromA.first?.threadID != fromB.first?.threadID)
        #expect(fromA.first?.dedupeKey != fromB.first?.dedupeKey)
        #expect(fromA.first?.connection == "A")
        #expect(fromB.first?.connection == "B")
    }

    @Test func answeringAnApprovalOnOneServerRemovesOnlyItsNotification() throws {
        var planner = NotificationPlanner()
        let fromA = posts(
            planner.plan(
                .approvalWaiting(onA, requestID: "r1", command: "ls"), context: context(), preferences: .init()))
        let fromB = posts(
            planner.plan(
                .approvalWaiting(onB, requestID: "r1", command: "ls"), context: context(), preferences: .init()))
        let first = try #require(fromA.first)
        let second = try #require(fromB.first, "same chat and request id on two servers: both are told")
        let removed = planner.plan(
            .approvalResolved(onA.key, requestID: "r1"), context: context(), preferences: .init())
        #expect(removed == [.remove([first.id])])
        #expect(first.id != second.id, "B's approval notification stays")
    }

    @Test func theChatOnScreenIsTheOneOnItsOwnServer() {
        var planner = NotificationPlanner()
        let looking = context(onScreen: onA.key, active: true)
        #expect(posts(planner.plan(ended(onA), context: looking, preferences: .init())).isEmpty)
        #expect(
            posts(planner.plan(ended(onB), context: looking, preferences: .init())).count == 1,
            "the same chat id on another server is not the chat on screen")
    }

    /// After a server switch the new server's chat with the same id is a different chat: it neither ends the old
    /// server's turn nor resolves its approval.
    @Test func theWatcherKeepsServersApart() {
        var watcher = TurnWatcher()
        let runningWithApproval = ChatActivity(isRunning: true, approval: .init(id: "r1", command: "ls"))
        _ = watcher.observe(onA, runningWithApproval, now: start)
        let idleOnB = watcher.observe(onB, ChatActivity(isRunning: false), now: start.addingTimeInterval(5))
        #expect(idleOnB.isEmpty, "B's idle chat c1 neither ends A's turn nor resolves A's approval")
        #expect(watcher.runningFor(onA.key, now: start.addingTimeInterval(10)) == 10)
        #expect(watcher.runningFor(onB.key, now: start.addingTimeInterval(10)) == nil)
    }

    @Test func aLocalChatIsScopedAsLocal() {
        let local = NotificationChat(id: "local-1", title: "Dinner", serverName: nil)
        #expect(local.key == NotificationChatKey(connection: nil, chatID: "local-1"))
        #expect(local.key.scope == "local/local-1")
    }

    // MARK: The tap link

    @Test func theTapLinkNamesItsServer() throws {
        let url = HermesURL.chat("c1", server: "A")
        #expect(HermesURL.chatID(from: url) == "c1")
        #expect(HermesURL.chatServer(from: url) == "A")
        let plain = HermesURL.chat("c1")
        #expect(HermesURL.chatServer(from: plain) == nil, "widget links name no server")
        #expect(HermesURL.chat("local-1", server: nil) == HermesURL.chat("local-1"))
    }
}
