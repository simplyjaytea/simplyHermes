#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The bots of every saved gateway, and what the Bots screen does to them (WP-42). The active gateway gives live
    /// rows over its WebSocket. The others give REST rows when they are connected. A gateway that stops answering keeps
    /// its last rows, marked retained.
    @MainActor
    @Observable
    final class BotsModel {
        /// Every bot, once per install and profile. Pinned bots lead (`BotRoster.entries`).
        private(set) var entries: [BotRosterEntry] = []
        private(set) var sources: [BotRosterSource] = []
        private(set) var isLoading = false
        /// The last failure, shown above the list. Nil once cleared or once an action works.
        var errorMessage: String?
        /// The search text. Matching ignores case and one leading `@`.
        var query = ""

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let profiles: ProfilesModel?
        @ObservationIgnored private let shell: ShellModel
        /// The last good read of each gateway, kept while it does not answer.
        @ObservationIgnored private var lastReads: [UUID: GatewayRead] = [:]

        private struct GatewayRead {
            let rows: [BotRosterRow]
            let installID: String?
        }

        init(connections: ConnectionsModel, profiles: ProfilesModel?, shell: ShellModel) {
            self.connections = connections
            self.profiles = profiles
            self.shell = shell
        }

        /// The sections the list draws: one per gateway when there are two or more, hidden bots last.
        var sections: [BotRosterSection] {
            BotRoster.sections(entries, sources: sources, query: query)
        }

        /// The search box shows with two or more gateways, eight or more bots, or a query (WP-42 spec, section 2).
        var showsSearch: Bool {
            sources.count > 1 || entries.count >= 8 || !query.isEmpty
        }

        /// Profile names on the active gateway. New Agent checks its name against them.
        var activeProfileNames: Set<String> {
            Set(entries.filter { $0.connectionID == connections.active?.id }.map(\.profile))
        }

        /// The profiles New Agent can clone from: the default first, then the rest by name.
        var cloneSources: [String] {
            let names = activeProfileNames
            let rest = names.subtracting(["default"]).sorted()
            return (names.contains("default") ? ["default"] : []) + rest
        }

        /// What a bot is doing right now. A running turn in its Bot Chat counts as active.
        func activity(of entry: BotRosterEntry, now: Date = Date()) -> BotActivity {
            BotRoster.activity(
                lastActive: entry.lastActive, workerActiveAt: entry.workerActiveAt,
                runningTurn: entry.canonicalSessionID.map(shell.isStreaming) ?? false,
                now: now.timeIntervalSince1970)
        }

        /// Reads every saved gateway. Call on appear, on pull to refresh, and when the active gateway changes.
        func reload() async {
            guard let manager = connections.manager else { return }
            isLoading = true
            var built: [BotRosterSource] = []
            for connection in connections.connections {
                built.append(await read(connection, manager: manager))
            }
            isLoading = false
            sources = built
            entries = BotRoster.entries(built)
        }

        /// Opens a bot's Bot Chat, creating it on first use (WP-42 spec, section 3). Only bots on the active gateway open.
        func openBotChat(_ entry: BotRosterEntry) async {
            guard entry.status == .ready, let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else { return }
            do {
                let client = BotClient(gateway: try await manager.client(for: connection))
                let lookup = try await client.findBotChat(
                    profile: entry.profile, rosterKnowsChat: entry.canonicalSessionID != nil)
                let chatID: String
                switch lookup {
                case .found(let openID, _): chatID = openID
                case .none: chatID = try await client.createBotChat(profile: entry.profile)
                case .inconsistent: throw BotError.chatInconsistent(entry.profile)
                }
                // The gateway works as this bot from here on, so the chat's calls carry its profile.
                await manager.setProfile(entry.profile, for: connection.id)
                profiles?.select(entry.profile)
                shell.openBotChat(
                    SessionListItem(
                        id: chatID, title: entry.title, time: nil, isPinned: entry.isPinned,
                        serverName: connection.name))
            } catch {
                errorMessage = Self.message(for: error)
            }
        }

        /// Creates a bot on the active gateway. Nil when nothing was created. A bot whose look did not save still counts,
        /// and the list says so.
        func createAgent(_ draft: NewAgentDraft) async -> BotClient.CreatedAgent? {
            guard let connection = connections.active, let manager = connections.manager else { return nil }
            do {
                let client = BotClient(gateway: try await manager.client(for: connection))
                let created = try await client.createAgent(draft, existingProfiles: activeProfileNames)
                await reload()
                if !created.lookSaved {
                    errorMessage =
                        "\(created.profile) was created, but its title or avatar did not save. Edit it from its menu."
                }
                return created
            } catch {
                errorMessage = Self.message(for: error)
                return nil
            }
        }

        /// Saves the Edit sheet. Only the fields that changed are written, as Desktop writes them.
        @discardableResult
        func saveEdits(of entry: BotRosterEntry, edit: BotEdit) async -> Bool {
            guard entry.status == .ready, let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else { return false }
            do {
                let client = BotClient(gateway: try await manager.client(for: connection))
                if edit.title != entry.title || edit.isPinned != entry.isPinned || edit.isHidden != entry.isHidden {
                    try await client.updateNamespace(
                        profile: entry.profile, namespace: BotMetaNamespace.desktop
                    ) { meta in
                        // Desktop's title is only written when it changed, so a bot without one keeps none.
                        if edit.title != entry.title { meta.title = edit.title }
                        meta.pinned = edit.isPinned
                        meta.hidden = edit.isHidden
                    }
                }
                if edit.avatar != entry.avatar {
                    try await client.updateNamespace(
                        profile: entry.profile, namespace: BotMetaNamespace.app
                    ) { object in
                        object = BotAppLook(avatar: edit.avatar).applied(to: object)
                    }
                }
                if edit.role != (entry.role ?? "") {
                    try await client.setRole(profile: entry.profile, role: edit.role)
                }
                await reload()
                return true
            } catch {
                errorMessage = Self.message(for: error)
                return false
            }
        }

        // MARK: Private

        /// One gateway's rows. The active gateway's come over its WebSocket. The others' come over REST when connected.
        private func read(_ connection: ServerConnection, manager: ConnectionManager) async -> BotRosterSource {
            let isPrimary = connection.id == connections.active?.id
            let fresh: GatewayRead?
            if isPrimary {
                fresh = await richRead(connection, manager: manager)
            } else {
                fresh = await restRead(connection, manager: manager)
            }
            if let fresh { lastReads[connection.id] = fresh }
            let shown = fresh ?? lastReads[connection.id]
            return BotRosterSource(
                connectionID: connection.id, label: connection.name, isPrimary: isPrimary,
                priority: Self.priority(of: connection), installID: shown?.installID, reachable: fresh != nil,
                isRich: isPrimary, rows: shown?.rows ?? [])
        }

        private func richRead(_ connection: ServerConnection, manager: ConnectionManager) async -> GatewayRead? {
            do {
                let client = try await manager.client(for: connection)
                let roster = try await BotClient(gateway: client).richRoster()
                return GatewayRead(rows: roster.rows, installID: roster.installID)
            } catch {
                return nil
            }
        }

        private func restRead(_ connection: ServerConnection, manager: ConnectionManager) async -> GatewayRead? {
            guard let rest = await manager.rest(for: connection.id) else { return nil }
            do {
                let rows = BotClient.restRows(try await rest.profiles())
                return GatewayRead(rows: rows, installID: (try? await rest.status())?.installId)
            } catch {
                return nil
            }
        }

        /// Lower wins when two gateways list the same install: ssh 1, gateway 2 (`BotRosterSource.priority`).
        private static func priority(of connection: ServerConnection) -> Int {
            switch connection.kind {
            case .ssh: 1
            case .gateway: 2
            }
        }

        /// The words a user reads for a failed bot action.
        static func message(for error: Error) -> String {
            if let bot = error as? BotError {
                switch bot {
                case .metaTooLarge: return "Those settings are too large to save."
                case .metaConflict: return "Someone else changed this bot at the same time. Try again."
                case .metaNotSaved, .roleNotSaved: return "The server did not save the change."
                case .profileNotFound: return "That bot is no longer on the server."
                case .chatInconsistent: return "Its chat could not be found, so nothing was opened."
                case .invalidDraft: return "Check the name and the model."
                }
            }
            if let rpc = error as? RPCError, rpc.code == 4062 {
                return "A bot with that name already exists."
            }
            return error.localizedDescription
        }
    }
#endif
