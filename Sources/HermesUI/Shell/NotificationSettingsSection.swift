#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UserNotifications

    /// Settings › Notifications: a reply finished or an approval waiting, while simplyHermes runs. The system prompt
    /// for permission only ever comes from the Turn on button here, never at launch.
    public struct NotificationSettingsSection: View {
        @AppStorage(NotificationPreferences.replyFinishedKey) private var replyFinished = true
        @AppStorage(NotificationPreferences.approvalWaitingKey) private var approvalWaiting = true
        @AppStorage(NotificationPreferences.showContentKey) private var showContent = false
        @AppStorage(NotificationPreferences.soundKey) private var sound = true
        @State private var status: UNAuthorizationStatus?
        @Environment(\.scenePhase) private var scenePhase

        public init() {}

        public var body: some View {
            Section {
                permissionRow
                Toggle("Reply finished", isOn: $replyFinished)
                    .accessibilityIdentifier("settings.notifications.reply")
                Toggle("Approval waiting", isOn: $approvalWaiting)
                    .accessibilityIdentifier("settings.notifications.approval")
                Toggle("Show message text", isOn: $showContent)
                    .accessibilityIdentifier("settings.notifications.content")
                Toggle("Sound", isOn: $sound)
                    .accessibilityIdentifier("settings.notifications.sound")
            } header: {
                Text("Notifications")
            } footer: {
                Text(
                    "Notifications arrive while simplyHermes is open or kept running. Turn on Keep bots live to get "
                        + "them reliably. With message text off, they never show a chat title, a reply or a command.")
            }
            .task(id: scenePhase) { await refreshStatus() }
        }

        @ViewBuilder
        private var permissionRow: some View {
            switch status {
            case .authorized, .provisional, .ephemeral:
                LabeledContent("Status", value: "Allowed")
                    .accessibilityIdentifier("settings.notifications.status")
            case .denied:
                LabeledContent("Status", value: "Off in iOS Settings")
                    .accessibilityIdentifier("settings.notifications.status")
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityIdentifier("settings.notifications.openSettings")
            case .notDetermined:
                Button("Turn on notifications") { Task { await requestPermission() } }
                    .accessibilityIdentifier("settings.notifications.turnOn")
            case nil:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }

        private func refreshStatus() async {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }

        private func requestPermission() async {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
        }
    }
#endif
