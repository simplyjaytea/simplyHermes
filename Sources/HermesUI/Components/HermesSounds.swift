#if canImport(UIKit)
    import AudioToolbox
    import SwiftUI

    /// Subtle sounds for send, approval and turn done (plan Q48). Off by default. They use system sounds, which
    /// the silent switch always mutes.
    public enum HermesSounds {
        /// `UserDefaults.standard` key for the Settings switch.
        public static let key = "soundsEnabled"

        public enum Cue {
            case send
            case approval
            case turnDone

            /// Built-in iOS sound ids. Placeholders until custom sounds are chosen.
            var systemSoundID: SystemSoundID {
                switch self {
                case .send: 1004
                case .approval: 1007
                case .turnDone: 1054
                }
            }
        }

        /// Plays `cue` when the switch is on.
        @MainActor
        public static func play(_ cue: Cue, defaults: UserDefaults = .standard) {
            guard defaults.bool(forKey: key) else { return }
            AudioServicesPlaySystemSound(cue.systemSoundID)
        }
    }

    /// Settings > Sounds.
    public struct SoundsSettingsSection: View {
        @AppStorage(HermesSounds.key) private var enabled = false

        public init() {}

        public var body: some View {
            Section {
                Toggle("Play sounds", isOn: $enabled)
                    .accessibilityIdentifier("settings.sounds")
            } header: {
                Text("Sounds")
            } footer: {
                Text(
                    "A soft sound when you send, when Hermes needs approval, and when a reply finishes. The silent switch mutes them."
                )
            }
        }
    }
#endif
