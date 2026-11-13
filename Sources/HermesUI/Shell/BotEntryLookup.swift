#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// The bot a chat belongs to, for its header: the roster entry that owns the chat, the one with the same title, the
    /// one for the chosen profile, or a stand-in built from the chosen profile. Pure: it reads only what it is given.
    enum BotEntryLookup {
        @MainActor
        static func entry(
            for sessionID: String, sessionTitle: String?, bots: BotsModel?, profiles: ProfilesModel?,
            connections: ConnectionsModel?
        ) -> BotRosterEntry? {
            if let entry = bots?.entries.first(where: { $0.canonicalSessionID == sessionID }) {
                return entry
            }
            if let sessionTitle, let entry = bots?.entries.first(where: { $0.title == sessionTitle }) {
                return entry
            }
            if let chosen = profiles?.selection.chosen {
                if let entry = bots?.entries.first(where: { $0.profile == chosen }) {
                    return entry
                }
            }
            guard let connection = connections?.active else { return nil }
            let profile = profiles?.selection.chosen ?? "default"
            let title = sessionTitle ?? ProfileSelection.title(of: profiles?.selection.current) ?? profile
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
                canonicalSessionID: sessionID,
                activity: Date().timeIntervalSince1970 * 1000
            )
        }
    }
#endif
