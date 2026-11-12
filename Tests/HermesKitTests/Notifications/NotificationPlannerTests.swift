import Foundation
import Testing

@testable import HermesKit

struct NotificationPlannerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let chat = NotificationChat(id: "s1", title: "Backup cron", serverName: "home")
    private let local = NotificationChat(id: "local-1", title: "Dinner", serverName: nil)

    private typealias Context = NotificationContext

    private func context(active: Bool = false, onScreen: String? = nil, many servers: Bool = false) -> Context {
        context(active: active, onScreen: onScreen, servers: servers, at: 60)
    }

    private func context(active: Bool, onScreen: String?, servers: Bool, at sec: Double) -> Context {
        NotificationContext(
            appIsActive: active, chatOnScreen: onScreen, multipleServers: servers, now: start.addingTimeInterval(sec))
    }

    private func context(at sec: Double) -> Context {
        context(active: false, onScreen: nil, servers: false, at: sec)
    }

    private func ended(
        _ chat: NotificationChat? = nil, outcome: NotificationEvent.Outcome = .done, endedAfter: Double = 30,
        reply: String = "The NAS rejected the key."
    ) -> NotificationEvent {
        .turnEnded(
            chat ?? self.chat, startedAt: start, endedAt: start.addingTimeInterval(endedAfter), outcome: outcome,
            reply: reply)
    }

    private func posts(_ actions: [NotificationAction]) -> [NotificationRequest] {
        actions.compactMap { if case .post(let request) = $0 { request } else { nil } }
    }

    // MARK: When

    @Test(arguments: [
        // active, on screen, posts
        (false, nil as String?, true), (false, "s1", true), (true, nil, true), (true, "other", true),
        (true, "s1", false),
    ])
    func aFinishedReplyIsToldUnlessItsChatIsOnScreen(active: Bool, onScreen: String?, posts expected: Bool) {
        var planner = NotificationPlanner()
        let actions = planner.plan(ended(), context: context(active: active, onScreen: onScreen), preferences: .init())
        #expect(!posts(actions).isEmpty == expected)
    }

    @Test func aStoppedTurnPostsNothing() {
        var planner = NotificationPlanner()
        #expect(planner.plan(ended(outcome: .stopped), context: context(), preferences: .init()).isEmpty)
    }

    @Test func theSameTurnTwiceIsOneNotificationAndANewTurnReplacesIt() {
        var planner = NotificationPlanner()
        let first = posts(planner.plan(ended(), context: context(), preferences: .init()))
        #expect(first.count == 1)
        #expect(planner.plan(ended(), context: context(at: 90), preferences: .init()).isEmpty, "a replay")
        let next = NotificationEvent.turnEnded(
            chat, startedAt: start.addingTimeInterval(100), endedAt: start.addingTimeInterval(120), outcome: .done,
            reply: "Done again")
        let second = posts(planner.plan(next, context: context(at: 130), preferences: .init()))
        #expect(second.count == 1)
        #expect(second[0].id == first[0].id, "same id: the chat's newer reply replaces the older notification")
        #expect(second[0].threadID == "s1")
        #expect(second[0].dedupeKey != first[0].dedupeKey)
    }

    @Test func aReplyLearnedOfMoreThanTenMinutesLateIsDropped() {
        var planner = NotificationPlanner()
        let late = context(at: 30 + NotificationPlanner.staleAfter + 1)
        #expect(planner.plan(ended(), context: late, preferences: .init()).isEmpty)
        var onTime = NotificationPlanner()
        #expect(
            !onTime.plan(ended(), context: context(at: 30 + NotificationPlanner.staleAfter), preferences: .init())
                .isEmpty)
    }

    @Test func eachSwitchTurnsItsEventOff() {
        var planner = NotificationPlanner()
        let off = NotificationPreferences(replyFinished: false, approvalWaiting: false)
        #expect(planner.plan(ended(), context: context(), preferences: off).isEmpty)
        #expect(planner.plan(ended(outcome: .failed), context: context(), preferences: off).isEmpty)
        #expect(
            planner.plan(
                .approvalWaiting(chat, requestID: "r1", command: "rm -rf build"), context: context(),
                preferences: off
            ).isEmpty)
    }

    @Test func anApprovalPostsOnceAndIsRemovedWhenAnswered() {
        var planner = NotificationPlanner()
        let waiting = NotificationEvent.approvalWaiting(chat, requestID: "r1", command: "rm -rf build")
        let posted = posts(planner.plan(waiting, context: context(), preferences: .init()))
        #expect(posted.count == 1)
        #expect(posted[0].kind == .approval)
        #expect(planner.plan(waiting, context: context(), preferences: .init()).isEmpty)
        let resolved = planner.plan(
            .approvalResolved(chatID: "s1", requestID: "r1"), context: context(), preferences: .init())
        #expect(resolved == [.remove([posted[0].id])])
    }

    @Test func approvalsInOneChatHaveTheirOwnNotifications() {
        var planner = NotificationPlanner()
        let first = posts(
            planner.plan(
                .approvalWaiting(chat, requestID: "r1", command: "a"), context: context(),
                preferences: .init()))
        let second = posts(
            planner.plan(
                .approvalWaiting(chat, requestID: "r2", command: "b"), context: context(),
                preferences: .init()))
        #expect(first[0].id != second[0].id)
    }

    // MARK: What it says

    @Test func contentIsHiddenByDefault() {
        var planner = NotificationPlanner()
        let reply = posts(planner.plan(ended(), context: context(many: true), preferences: .init()))[0]
        #expect(reply.title == "Hermes replied")
        #expect(reply.body == NotificationPlanner.hiddenBody)
        let approval = posts(
            planner.plan(
                .approvalWaiting(chat, requestID: "r1", command: "wipe-disk --now"),
                context: context(), preferences: .init()))[0]
        #expect(approval.title == "Hermes needs your OK")
        #expect(!approval.body.contains("wipe"))
        #expect(!approval.title.contains("Backup"))
    }

    @Test func contentOnNamesTheChatAndTheFirstLine() {
        var planner = NotificationPlanner()
        let shown = NotificationPreferences(showContent: true)
        let reply = posts(
            planner.plan(
                ended(reply: "## Result\n**The NAS** rejected the `key`."),
                context: context(), preferences: shown))[0]
        #expect(reply.title == "Hermes replied: Backup cron")
        #expect(reply.body == "Result")
        let approval = posts(
            planner.plan(
                .approvalWaiting(chat, requestID: "r1", command: "rm -rf build/"),
                context: context(), preferences: shown))[0]
        #expect(approval.title == "Hermes needs your OK: Backup cron")
        #expect(approval.body == "rm -rf build/")
    }

    @Test func aHiddenChatTitleStaysHiddenWithContentOn() {
        var planner = NotificationPlanner()
        let request = posts(
            planner.plan(
                ended(), context: context(),
                preferences: NotificationPreferences(showContent: true, showChatTitle: false)))[0]
        #expect(request.title == "Hermes replied: a chat")
        #expect(!request.title.contains("Backup"))
    }

    @Test func theServerIsNamedOnlyWhenSeveralAreSavedAndALocalChatSaysThisIPhone() {
        let shown = NotificationPreferences(showContent: true)
        var one = NotificationPlanner()
        #expect(
            posts(one.plan(ended(), context: context(many: false), preferences: shown))[0].title
                == "Hermes replied: Backup cron")
        var many = NotificationPlanner()
        #expect(
            posts(many.plan(ended(), context: context(many: true), preferences: shown))[0].title
                == "Hermes replied: Backup cron on home")
        var localPlanner = NotificationPlanner()
        #expect(
            posts(localPlanner.plan(ended(local), context: context(many: true), preferences: shown))[0].title
                == "Hermes replied: Dinner · On this iPhone")
    }

    @Test func aFailedTurnSaysSoWithoutTheReply() {
        var planner = NotificationPlanner()
        let request = posts(
            planner.plan(
                ended(outcome: .failed), context: context(),
                preferences: NotificationPreferences(showContent: true)))[0]
        #expect(request.title == "Hermes stopped with an error: Backup cron")
        #expect(request.body == NotificationPlanner.hiddenBody)
    }

    @Test func markdownIsStrippedAndLongLinesCut() {
        #expect(NotificationPlanner.plainFirstLine("```swift\nlet x = 1\n```\n> - **Done**: `ok`") == "Done: ok")
        #expect(NotificationPlanner.plainFirstLine("\n\n") == "")
        let long = String(repeating: "a", count: 300)
        let cut = NotificationPlanner.cut(long)
        #expect(cut.count == NotificationPlanner.bodyLimit)
        #expect(cut.hasSuffix("…"))
        #expect(NotificationPlanner.cut("short") == "short")
    }

    @Test func soundFollowsTheSetting() {
        var planner = NotificationPlanner()
        #expect(
            posts(planner.plan(ended(), context: context(), preferences: NotificationPreferences(sound: false)))[0]
                .playsSound == false)
    }

    // MARK: Settings

    @Test func preferencesDefaultToContentHiddenAndRoundTrip() throws {
        let name = "NotificationPlannerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = NotificationPreferences.load(from: defaults)
        #expect(fresh == NotificationPreferences())
        #expect(fresh.showContent == false)
        var changed = fresh
        changed.replyFinished = false
        changed.showContent = true
        changed.sound = false
        changed.save(to: defaults)
        #expect(NotificationPreferences.load(from: defaults) == changed)
        #expect(NotificationPreferences.load(from: defaults, showChatTitle: false).showChatTitle == false)
    }
}
