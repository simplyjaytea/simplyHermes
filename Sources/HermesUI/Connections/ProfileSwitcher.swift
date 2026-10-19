#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The profile chip in the header: one tap opens the bots of this server, and the menu's Bot settings item opens the
    /// settings of the bot (WP-41). Shown while connected, so Bot settings is reachable even with one profile.
    public struct ProfileSwitcher: View {
        private let profiles: ProfilesModel
        private let connections: ConnectionsModel
        @State private var showsBotSettings = false

        public init(profiles: ProfilesModel, connections: ConnectionsModel) {
            self.profiles = profiles
            self.connections = connections
        }

        private var isConnected: Bool {
            guard let id = connections.active?.id, case .connected = connections.phase(of: id) else { return false }
            return true
        }

        public var body: some View {
            Group {
                if isConnected {
                    Menu {
                        ForEach(profiles.selection.rows) { row in
                            Button {
                                profiles.select(row.name)
                            } label: {
                                if row.isCurrent {
                                    Label(row.title, systemImage: "checkmark")
                                } else {
                                    Text(row.title)
                                }
                            }
                        }
                        Divider()
                        Button {
                            showsBotSettings = true
                        } label: {
                            Label("Bot settings…", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("profileSwitcher.botSettings")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle").font(HermesFont.caption)
                            Text(profiles.selection.label)
                                .font(HermesFont.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(HermesFont.caption)
                        }
                    }
                    .accessibilityLabel("Profile: \(profiles.selection.label)")
                    .accessibilityIdentifier("profileSwitcher")
                }
            }
            .task(id: "\(connections.active?.id.uuidString ?? "none")-\(isConnected)") {
                await profiles.refresh()
            }
            .sheet(isPresented: $showsBotSettings) {
                BotSettingsSheet(profiles: profiles, connections: connections)
            }
        }
    }
#endif
