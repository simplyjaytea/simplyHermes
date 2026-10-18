#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// "Keep bots live" (plan decision D1, option B): while a bot works, the app holds a silent audio
    /// session so iOS keeps it running and the Live Activity stays current. Off by default.
    public enum KeepBotsLiveSetting {
        /// The key for the switch, in ``store()``.
        public static let key = "keepBotsLive"
        /// Set once the battery note has been shown.
        public static let noteShownKey = "keepBotsLiveNoteShown"

        /// The App Group this install is signed with, if any. Looked up at run time because SideStore renames it.
        private static let groupID: String? = {
            let resolution = SharedContainer.resolve(
                infoDictionary: Bundle.main.infoDictionary,
                containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            )
            if case .appGroup(let id, _) = resolution { return id }
            return nil
        }()

        /// True when the switch lives in the App Group, so Control Center and the app see the same value.
        public static var isShared: Bool { groupID != nil }

        /// Where the switch is kept: the App Group when there is one, else this app's own defaults. A value set before
        /// the switch moved to the App Group is copied over once.
        public static func store() -> UserDefaults {
            guard let groupID, let shared = UserDefaults(suiteName: groupID) else { return .standard }
            if shared.object(forKey: key) == nil, let earlier = UserDefaults.standard.object(forKey: key) as? Bool {
                shared.set(earlier, forKey: key)
            }
            return shared
        }
    }

    /// Settings > Bots: the switch, and a one-time battery note when it is first turned on.
    public struct BotsSettingsSection: View {
        @AppStorage(KeepBotsLiveSetting.key, store: KeepBotsLiveSetting.store()) private var keepBotsLive = false
        @AppStorage(KeepBotsLiveSetting.noteShownKey) private var noteShown = false
        @State private var showsNote = false

        public init() {}

        public var body: some View {
            Section {
                Toggle("Keep bots live", isOn: $keepBotsLive)
                    .accessibilityIdentifier("settings.keepBotsLive")
            } header: {
                Text("Bots")
            } footer: {
                Text(
                    """
                    Keeps simplyHermes running in the background while a bot works, so the Live Activity \
                    and alerts stay current. Stops when the last bot finishes.
                    """
                )
            }
            .onChange(of: keepBotsLive) { _, isOn in
                if isOn && !noteShown {
                    noteShown = true
                    showsNote = true
                }
            }
            .alert("Uses more battery", isPresented: $showsNote) {
                Button("Keep on") {}
                Button("Turn off", role: .cancel) { keepBotsLive = false }
            } message: {
                Text(
                    """
                    While a bot works, simplyHermes plays silent audio so iOS keeps it running. If iOS \
                    still closes the app, the Live Activity shows "Open simplyHermes to refresh".
                    """
                )
            }
        }
    }

    /// The Settings tab until WP-53 builds the full Settings screen.
    public struct SettingsPreviewList: View {
        public init() {}

        public var body: some View {
            Form {
                BotsSettingsSection()
                SoundsSettingsSection()
                TipsSettingsSection()
                Section("Support") {
                    NavigationLink {
                        BugReportScreen(connections: nil)
                    } label: {
                        Label("Report a bug", systemImage: "ladybug")
                    }
                    .accessibilityIdentifier("settings.reportBug")
                    NavigationLink {
                        GitHubAccountView()
                    } label: {
                        Label("GitHub account", systemImage: "person.badge.key")
                    }
                    .accessibilityIdentifier("settings.githubAccount")
                }
                Section {
                    Text("More settings are coming in WP-53.")
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .navigationTitle("Settings")
        }
    }
#endif
