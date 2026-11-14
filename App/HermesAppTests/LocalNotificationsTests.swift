import Foundation
import HermesKit
import Testing
import UserNotifications

@testable import simplyHermes

/// The app layer of local notifications (#136): planned requests reach the system center with the right identity,
/// grouping, level and sound, and an answered approval is removed. A fake center records the calls.
@MainActor
struct LocalNotificationsTests {
    private final class FakeCenter: NotificationCenterClient {
        var added: [UNNotificationRequest] = []
        var removedDelivered: [[String]] = []
        var removedPending: [[String]] = []

        /// Records the system request the real center would get.
        func add(_ request: NotificationRequest) async throws {
            added.append(LocalNotifications.systemRequest(request))
        }
        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            removedDelivered.append(identifiers)
        }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removedPending.append(identifiers)
        }
    }

    private let chat = NotificationChat(id: "s1", title: "Backup", serverName: "home")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func defaults() -> UserDefaults {
        let name = "LocalNotificationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func context(active: Bool = false, onScreen: String? = nil) -> NotificationContext {
        NotificationContext(
            appIsActive: active, chatOnScreen: onScreen.map { NotificationChatKey(connection: nil, chatID: $0) },
            multipleServers: false, now: start)
    }

    private func settle(_ center: FakeCenter, count: Int) async {
        for _ in 0..<100 where center.added.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aFinishedReplyIsPostedOnceWithItsChatAndHiddenText() async {
        let center = FakeCenter()
        let poster = LocalNotifications(center: center, defaults: defaults())
        let event = NotificationEvent.turnEnded(
            chat, turnID: "row-2", startedAt: start, endedAt: start, outcome: .done, reply: "secret text")
        poster.handle(event, context: context())
        poster.handle(event, context: context())
        await settle(center, count: 1)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(center.added.count == 1, "never twice")
        let request = center.added[0]
        #expect(request.identifier == "reply.local/s1")
        #expect(request.content.threadIdentifier == "local/s1")
        #expect(request.content.userInfo["chat"] as? String == "s1")
        #expect(request.content.interruptionLevel == .active, "no Time Sensitive entitlement needed")
        #expect(request.content.title == "Hermes replied")
        #expect(!request.content.body.contains("secret"), "text hidden by default")
        #expect(request.content.sound != nil)
    }

    @Test func nothingForTheChatOnScreenOrAStoppedTurn() async {
        let center = FakeCenter()
        let poster = LocalNotifications(center: center, defaults: defaults())
        poster.handle(
            .turnEnded(chat, turnID: "row-2", startedAt: start, endedAt: start, outcome: .done, reply: ""),
            context: context(active: true, onScreen: "s1"))
        poster.handle(
            .turnEnded(chat, turnID: "row-3", startedAt: start, endedAt: start, outcome: .stopped, reply: ""),
            context: context())
        try? await Task.sleep(for: .milliseconds(100))
        #expect(center.added.isEmpty)
    }

    @Test func anApprovalIsPostedThenRemovedWhenAnswered() async {
        let center = FakeCenter()
        let poster = LocalNotifications(center: center, defaults: defaults())
        poster.handle(.approvalWaiting(chat, requestID: "r1", command: "rm -rf build"), context: context())
        await settle(center, count: 1)
        #expect(center.added.first?.identifier == "approval.local/s1.r1")
        poster.handle(.approvalResolved(chat.key, requestID: "r1"), context: context())
        #expect(center.removedDelivered == [["approval.local/s1.r1"]])
        #expect(center.removedPending == [["approval.local/s1.r1"]])
    }

    @Test func soundOffIsSilent() async {
        let center = FakeCenter()
        let settings = defaults()
        NotificationPreferences(sound: false).save(to: settings)
        let poster = LocalNotifications(center: center, defaults: settings)
        poster.handle(.approvalWaiting(chat, requestID: "r1", command: "ls"), context: context())
        await settle(center, count: 1)
        #expect(center.added.first?.content.sound == nil)
    }
}
