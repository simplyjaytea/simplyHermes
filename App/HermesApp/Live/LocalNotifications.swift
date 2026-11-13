import Foundation
import HermesKit
import HermesUI
import OSLog
import UIKit
import UserNotifications

/// The calls the poster makes on the notification center, so app tests can use a fake. Main-actor bound, as the
/// poster is (review m3 on #136). It takes the app's own Sendable ``NotificationRequest``, never a UserNotifications
/// object: those are built inside ``SystemNotificationCenter``, so nothing non-Sendable crosses an isolation boundary
/// whatever the SDK says about `UNNotificationRequest`.
@MainActor
protocol NotificationCenterClient: AnyObject {
    func add(_ request: NotificationRequest) async throws
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

/// The system notification center behind ``NotificationCenterClient``.
final class SystemNotificationCenter: NotificationCenterClient {
    func add(_ request: NotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(LocalNotifications.systemRequest(request))
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Local notifications for a finished reply and a waiting approval. ``NotificationPlanner`` (HermesKit) decides;
/// this turns its actions into system calls and opens the chat on a tap. It asks for permission only from Settings ›
/// Notifications, never by itself.
///
/// Honest limit: a local notification needs the app running. With Keep bots live off, iOS suspends the app about 30
/// seconds after it leaves the screen, and nothing more is noticed until it opens again.
@MainActor
final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotifications()

    private var planner = NotificationPlanner()
    private let center: NotificationCenterClient
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.simplyjaytea.simplyhermes", category: "LocalNotifications")

    init(center: NotificationCenterClient = SystemNotificationCenter(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        super.init()
    }

    /// Becomes the system delegate, so taps open the chat and a notification for another chat shows in the app too.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Plans `event` with the current settings and carries it out.
    func handle(_ event: NotificationEvent, context: NotificationContext) {
        let preferences = NotificationPreferences.load(
            from: defaults, showChatTitle: QuickActionStore(defaults: defaults).showTitle)
        for action in planner.plan(event, context: context, preferences: preferences) {
            perform(action)
        }
    }

    private func perform(_ action: NotificationAction) {
        switch action {
        case .remove(let ids):
            center.removeDeliveredNotifications(withIdentifiers: ids)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        case .post(let request):
            Task {
                do {
                    try await center.add(request)
                } catch {
                    // Not allowed, or the system refused it: nothing to show, and nothing is lost (the chat has it).
                    logger.notice("Notification not posted: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// The system request for a planned one. Approvals are ordinary (`.active`) notifications: the Time Sensitive
    /// entitlement is optional and unverified on SideStore and Signulous builds, so nothing depends on it.
    nonisolated static func systemRequest(_ request: NotificationRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.threadIdentifier = request.threadID
        var info: [String: String] = ["chat": request.chatID, "dedupe": request.dedupeKey]
        info["server"] = request.connection
        content.userInfo = info
        content.interruptionLevel = .active
        if request.playsSound { content.sound = .default }
        return UNNotificationRequest(identifier: request.id, content: content, trigger: nil)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The planner already left out the chat on screen, so whatever arrives here is about another chat.
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let chat = info["chat"] as? String else { return }
        // The chat link with its server: the app opens it only while that server is active, so a tap never opens the
        // same chat id on another server, and never switches servers by itself.
        let url = HermesURL.chat(chat, server: info["server"] as? String)
        await MainActor.run { _ = UIApplication.shared.open(url) }
    }
}
