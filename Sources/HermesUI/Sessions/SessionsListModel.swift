#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One row of the sessions list.
    public struct SessionListItem: Identifiable, Hashable, Sendable {
        public let id: String
        public var title: String
        /// Short time label such as `14:05` or `Yesterday`.
        public var time: String?
        public var isPinned: Bool
        public var serverName: String
    }

    /// One time section of the sessions list.
    public struct SessionListSection: Identifiable, Hashable, Sendable {
        public var group: SessionGroup
        public var items: [SessionListItem]
        public var id: String { group.id }
    }

    /// The sessions list of the active connection (WP-40): cached sessions show at once, a refresh follows, and
    /// pin, archive and delete go through ``SessionLibrary``.
    @MainActor
    @Observable
    public final class SessionsListModel {
        public private(set) var sections: [SessionListSection] = []
        public private(set) var isRefreshing = false
        /// Set when the last refresh or change failed. The cached list stays on screen.
        public private(set) var errorText: String?
        public var searchText = ""
        public private(set) var searchHits: [SessionSearchHit] = []

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let cache: HermesCache
        @ObservationIgnored private var library: SessionLibrary?
        @ObservationIgnored private var attachedID: UUID?
        @ObservationIgnored private var serverName = ""
        @ObservationIgnored private var onChange: (@MainActor ([SessionListItem]) -> Void)?

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

        /// Attaches to the active connection: shows its cache, then refreshes from the server.
        public func attach() async {
            guard let connection = connections.active, let manager = connections.manager else { return }
            if attachedID != connection.id {
                attachedID = connection.id
                serverName = connection.name
                library = SessionLibrary(
                    backend: ManagedSessionsBackend(manager: manager, connection: connection), cache: cache,
                    connection: connection.id.uuidString)
                await showCached()
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
                            serverName: name)
                    })
            }
            onChange?(items)
        }

        private static func title(of record: SessionRecord) -> String {
            let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? "Untitled chat" : title
        }
    }
#endif
