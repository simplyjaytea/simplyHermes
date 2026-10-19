#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Messaging section of Settings: channels, pairing requests and webhooks (WP-53c).
    struct SettingsMessagingSection: View {
        let connections: ConnectionsModel

        var body: some View {
            Section("Messaging") {
                NavigationLink {
                    MessagingChannelsView(connections: connections)
                } label: {
                    Label("Channels", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("settings.messaging.channels")
                NavigationLink {
                    PairingRequestsView(connections: connections)
                } label: {
                    Label("Pairing requests", systemImage: "person.crop.circle.badge.checkmark")
                }
                .accessibilityIdentifier("settings.messaging.pairing")
                NavigationLink {
                    WebhookListView(connections: connections)
                } label: {
                    Label("Webhooks", systemImage: "arrow.triangle.branch")
                }
                .accessibilityIdentifier("settings.messaging.webhooks")
            }
        }
    }
#endif
