#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > On-device: the switch that turns every on-device feature off (plan WP-65b). It is on by default, and
    /// the Apple model reads it through ``OnDeviceSettings``.
    public struct OnDeviceSettingsSection: View {
        @AppStorage(OnDeviceSettings.key) private var enabled = true

        public init() {}

        public var body: some View {
            Section {
                Toggle("On-device features", isOn: $enabled)
                    .accessibilityIdentifier("settings.onDevice")
                NavigationLink("On-device models") {
                    OnDeviceModelsScreen(isEnabled: $enabled)
                }
                .accessibilityIdentifier("settings.onDeviceModels")
                // Memory for local chats (local agent abilities, phase 1). Off until the app installs local chats.
                if let memory = LocalChatServices.shared?.memory {
                    NavigationLink("Memory") { LocalMemoryScreen(store: memory) }
                        .accessibilityIdentifier("settings.localMemory")
                }
            } header: {
                Text("On-device")
            } footer: {
                Text(
                    """
                    Offline chat, chat titles, summaries and prompt polish run on this iPhone. \
                    Turn this off to stop all of them.
                    """
                )
            }
        }
    }
#endif
