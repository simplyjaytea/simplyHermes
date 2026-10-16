#if canImport(UIKit)
    import SwiftUI
    import TipKit

    /// First-use tips, each shown once (plan Q51). Settings can turn all of them off.
    public enum HermesTips {
        /// `UserDefaults.standard` key for the Settings switch.
        public static let key = "tipsEnabled"

        /// Mirrors the Settings switch for tip rules.
        @Parameter static var isEnabled: Bool = true

        /// Call once at launch. `enabled` is false in UI tests, where a popover would cover controls.
        @MainActor
        public static func configure(enabled: Bool = true, defaults: UserDefaults = .standard) {
            let stored = defaults.object(forKey: key) as? Bool ?? true
            isEnabled = enabled && stored
            try? Tips.configure([.displayFrequency(.immediate)])
        }
    }

    /// Touch and hold Send to steer a running reply (plan Q23).
    struct SteerTip: Tip {
        var title: Text { Text("Steer the reply") }
        var message: Text? { Text("Touch and hold Send to add a note to the reply that is running.") }
        var image: Image? { Image(systemName: "arrow.turn.up.right") }
        var rules: [Rule] { [#Rule(HermesTips.$isEnabled) { $0 }] }
        var options: [any TipOption] { [Tips.MaxDisplayCount(1)] }
    }

    /// Settings > Tips.
    public struct TipsSettingsSection: View {
        @AppStorage(HermesTips.key) private var enabled = true

        public init() {}

        public var body: some View {
            Section {
                Toggle("Show tips", isOn: $enabled)
                    .accessibilityIdentifier("settings.tips")
            } footer: {
                Text("Short hints the first time you can use a feature.")
            }
            .onChange(of: enabled) { _, isOn in HermesTips.isEnabled = isOn }
        }
    }
#endif
