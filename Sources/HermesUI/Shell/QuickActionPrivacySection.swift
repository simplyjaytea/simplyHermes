#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings › Privacy: whether the last chat's title shows in the app icon's long-press menu, where anyone holding
    /// the phone can read it. When it's off, the item reads "Continue last chat".
    public struct QuickActionPrivacySection: View {
        @AppStorage(QuickActionStore.showTitleKey) private var showTitle = true

        public init() {}

        private var footer: String {
            "Touch and hold the simplyHermes icon to continue your last chat. When this is off, the shortcut says "
                + "\"\(QuickActionMenu.hiddenTitle)\" instead of the chat's title."
        }

        public var body: some View {
            Section {
                Toggle("Show chat title in app shortcuts", isOn: $showTitle)
                    .accessibilityIdentifier("settings.quickActionTitle")
            } header: {
                Text("Privacy")
            } footer: {
                Text(footer)
            }
        }
    }
#endif
