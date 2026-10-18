#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import UIKit

    /// One row of the sessions list.
    public struct SessionListItem: Identifiable, Hashable, Sendable {
        public let id: String
        public var title: String
        /// Short time label such as `14:05` or `Yesterday`.
        public var time: String?
        public var isPinned: Bool
        public var serverName: String
        /// The profile that owns the session. Nil when the server did not say.
        public var profile: String?

        /// The `@session:` text that names this session, for Copy link. Nil when it cannot be named.
        public var link: String? {
            profile.flatMap { SessionLink.format(SessionReference(profile: $0, sessionID: id)) }
        }
    }

    /// One time section of the sessions list.
    public struct SessionListSection: Identifiable, Hashable, Sendable {
        public var group: SessionGroup
        public var items: [SessionListItem]
        public var id: String { group.id }
    }

    /// A chat exported to a temporary JSON file, waiting for the share sheet.
    public struct ExportedChat: Identifiable, Hashable, Sendable {
        public var url: URL
        public var id: URL { url }
    }

    /// The sessions list of the active connection (WP-40): cached sessions show at once, a refresh follows, and
    /// pin, archive, delete, export and prune go through ``SessionLibrary``. Each profile keeps its own list.
    @MainActor
    @Observable
    public final class SessionsListModel {
        public private(set) var sections: [SessionListSection] = []
        public private(set) var isRefreshing = false
        /// Set when the last refresh or change failed. The cached list stays on screen.
        public private(set) var errorText: String?
        /// A short confirmation, such as "Removed 3 sessions." It stays until the next change.
        public private(set) var noticeText: String?
        /// The chat the share sheet shows after an export. The view clears it when the sheet closes.
        public var exportedChat: ExportedChat?
        public var searchText = ""
        public private(set) var searchHits: [SessionSearchHit] = []

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let cache: HermesCache
        @ObservationIgnored private var library: SessionLibrary?
        /// The connection and the profile the list is attached to. A change of either starts a new list.
        @ObservationIgnored private var attachedKey: String?
        /// The profile the user chose on the attached connection, or nil for the server's default.
        @ObservationIgnored private var attachedProfile: String?
        /// The profile the list shows, by name. Rows use it when a record does not name its owner.
        @ObservationIgnored private var listedProfile: String?
        @ObservationIgnored private var serverName = ""
        @ObservationIgnored private var onChange: (@MainActor ([SessionListItem]) -> Void)?

        private static let untitled = "Untitled chat"

        public init(connections: ConnectionsModel, cache: HermesCache) {
            self.connections = connections
            self.cache = cache
        }

        /// Called with all rows, in display order, after every change.
        public func observeItems(_ handler: @escaping @MainActor ([SessionListItem]) -> Void) {
            onChange = handler
        }

        public var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        }

        public var items: [SessionListItem] { sections.flatMap(\.items) }

        /// Attaches to the active connection and `profile` (nil is the server's default): shows its cache, then
        /// refreshes from the server. A different server or profile starts a new list.
        public func attach(profile: String?) async {
            guard let connection = connections.active, let manager = connections.manager else { return }
            let key = "\(connection.id.uuidString)|\(profile ?? "")"
            if attachedKey != key {
                attachedKey = key
                attachedProfile = profile
                listedProfile = nil
                serverName = connection.name
                library = SessionLibrary(
                    backend: ManagedSessionsBackend(manager: manager, connection: connection), cache: cache,
                    connection: key)
                await showCached()
            }
            // The REST calls carry the profile the list shows, so they cannot read another profile's chats. Set it
            // before every refresh, since a profile change made elsewhere may not have landed yet.
            if await manager.profile(of: connection.id) != profile {
                await manager.setProfile(profile, for: connection.id)
            }
            await refresh()
        }

        public func refresh() async {
            guard let library else { return }
            isRefreshing = true
            defer { isRefreshing = false }
            do {
                _ = try await library.refresh()
                errorText = nil
                if listedProfile == nil { listedProfile = await currentProfile() }
            } catch is CancellationError {
                return
            } catch {
                errorText = "Could not refresh. Showing saved chats."
            }
            await showCached()
        }

        public func togglePin(_ id: String) async {
            guard let item = items.first(where: { $0.id == id }) else { return }
            await run { try await $0.setPinned(id, !item.isPinned) }
        }

        public func archive(_ id: String) async {
            await run { try await $0.setArchived(id, true) }
        }

        public func delete(_ id: String) async {
            await run { try await $0.delete(id) }
        }

        public func rename(_ id: String, to title: String) async {
            await run { try await $0.rename(id, to: title) }
        }

        /// Downloads a chat as JSON, checks that it parses, and saves it to a temporary file for the share sheet.
        public func export(_ item: SessionListItem) async {
            guard let library else { return }
            let active = await currentProfile()
            do {
                let data = try await library.export(item.id, profile: item.profile, activeProfile: active)
                let title = item.title == Self.untitled ? nil : item.title
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                    SessionExport.fileName(title: title, sessionID: item.id))
                try data.write(to: url, options: .atomic)
                errorText = nil
                exportedChat = ExportedChat(url: url)
            } catch {
                errorText = "Could not export this chat. Try again."
            }
        }

        /// Copies the `@session:` text that names a chat, ready to paste into a message.
        public func copyLink(_ item: SessionListItem) {
            guard let link = item.link else { return }
            UIPasteboard.general.string = link
            noticeText = "Link copied."
        }

        /// Deletes ended sessions idle for more than `days` days. The server keeps live, pinned and archived sessions.
        /// Returns true when the server answered, so the sheet can close.
        public func prune(olderThanDays days: Int) async -> Bool {
            guard let library else { return false }
            guard let profile = await currentProfile() else {
                errorText = "Could not tell which profile to prune. Try again."
                return false
            }
            do {
                let answer = try await library.prune(SessionPruneFilter(olderThanDays: Double(days), profile: profile))
                errorText = nil
                noticeText = SessionPruneReport.removedCount(in: answer).map(Self.removedText) ?? "Done"
                await showCached()
                return true
            } catch {
                errorText = "Could not prune sessions. Try again."
                return false
            }
        }

        /// Opens the chat an `@session:` link names. A chat in another profile makes that profile the active one first.
        /// Returns a calm message when the chat cannot be opened, or nil when it is open.
        public func open(
            _ reference: SessionReference, in shell: ShellModel, profiles: ProfilesModel
        ) async -> String? {
            guard let connection = connections.active, let manager = connections.manager else {
                return "Connect to a server first."
            }
            guard (try? await manager.client(for: connection)) != nil else {
                return "Could not reach the server. Try again."
            }
            if profiles.selection.profiles.isEmpty { await profiles.refresh() }
            guard profiles.selection.profiles.contains(where: { $0.name == reference.profile }) else {
                return "This server has no profile named \(reference.profile)."
            }
            if profiles.selection.current?.name != reference.profile {
                profiles.select(reference.profile)
                await attach(profile: reference.profile)
            }
            if library == nil { await attach(profile: profiles.selection.chosen) }
            guard let library else { return "Could not open that chat. Try again." }
            do {
                let record = try await library.fetch(reference)
                shell.show(
                    SessionListItem(
                        id: record.id, title: Self.title(of: record), time: SessionGrouping.rowTime(record),
                        isPinned: record.pinned?.value == true, serverName: connection.name,
                        profile: reference.profile))
                return nil
            } catch RESTError.http(status: 404, _) {
                return "This chat no longer exists on this server."
            } catch {
                return "Could not open that chat. Try again."
            }
        }

        /// Searches message text; the view calls it from `.task(id: searchText)`, which cancels stale searches.
        public func runSearch() async {
            let text = searchText.trimmingCharacters(in: .whitespaces)
            guard let library, !text.isEmpty else {
                searchHits = []
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            searchHits = (try? await library.search(text)) ?? []
        }

        private func run(_ change: (SessionLibrary) async throws -> Void) async {
            guard let library else { return }
            do {
                try await change(library)
                errorText = nil
            } catch {
                errorText = "That change did not work. Try again."
            }
            await showCached()
        }

        /// The profile this list reads: the one it is attached to, else the server's default. Nil when the server cannot
        /// say.
        private func currentProfile() async -> String? {
            guard let connection = connections.active, let manager = connections.manager else { return nil }
            guard (try? await manager.client(for: connection)) != nil,
                let rest = await manager.rest(for: connection.id),
                let profiles = try? await rest.profiles()
            else { return nil }
            return ProfileSelection.resolve(profiles: profiles, stored: attachedProfile).current?.name
        }

        private func showCached() async {
            guard let library, let records = try? await library.cached() else { return }
            let now = Date()
            let name = serverName
            sections = SessionGrouping.sections(records, now: now).map { section in
                SessionListSection(
                    group: section.group,
                    items: section.sessions.map { record in
                        SessionListItem(
                            id: record.id, title: Self.title(of: record),
                            time: SessionGrouping.rowTime(record, now: now), isPinned: record.pinned?.value == true,
                            serverName: name, profile: record.profile ?? listedProfile)
                    })
            }
            onChange?(items)
        }

        private static func title(of record: SessionRecord) -> String {
            let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? untitled : title
        }

        private static func removedText(_ count: Int) -> String {
            count == 1 ? "Removed 1 session." : "Removed \(count) sessions."
        }
    }
#endif
