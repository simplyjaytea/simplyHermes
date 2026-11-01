#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftUI

    /// The profile chip in the header: one tap opens the bots of this server, and the menu's Bot settings item opens the
    /// settings of the bot (WP-41). Shown while connected, so Bot settings is reachable even with one profile.
    public struct ProfileSwitcher: View {
        private let profiles: ProfilesModel
        private let connections: ConnectionsModel
        private let bots: BotsModel?
        @State private var showsBotSettings = false

        public init(profiles: ProfilesModel, connections: ConnectionsModel) {
            self.profiles = profiles
            self.connections = connections
            self.bots = nil
        }

        init(profiles: ProfilesModel, connections: ConnectionsModel, bots: BotsModel?) {
            self.profiles = profiles
            self.connections = connections
            self.bots = bots
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
                if let entry = activeBotEntry {
                    BotSettingsScreen(entry: entry, connections: connections, rosterModel: bots)
                } else {
                    BotSettingsSheet(profiles: profiles, connections: connections)
                }
            }
        }

        private var activeBotEntry: BotRosterEntry? {
            guard let connection = connections.active else { return nil }
            let byConnection = bots?.entries.first(where: { $0.connectionID == connection.id && $0.profile == profile })
            let byProfile = bots?.entries.first(where: { $0.profile == profile })
            if let entry = byConnection ?? byProfile {
                return entry
            }
            let title = profiles.selection.current?.title ?? profile
            return BotRosterEntry(
                connectionID: connection.id,
                sourceLabel: connection.name,
                profile: profile,
                handle: profile,
                title: title,
                monogram: BotMonogram.text(for: title),
                tint: BotTint.name(for: profile),
                avatar: nil,
                status: .ready,
                isRetained: true,
                isPinned: false,
                isHidden: false,
                isDefault: profile == "default",
                role: nil,
                preview: nil,
                lastActive: nil,
                workerActiveAt: nil,
                canonicalSessionID: nil,
                activity: Date().timeIntervalSince1970 * 1000
            )
        }
    }
#endif
