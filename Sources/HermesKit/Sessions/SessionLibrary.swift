import Foundation

/// Which sessions `POST /api/sessions/prune` deletes. Only ended sessions match. Every field narrows the match.
public struct SessionPruneFilter: Sendable, Equatable, Encodable {
    /// Sessions that ended more than this many days ago. The server default is 90.
    public var olderThanDays: Double?
    /// Only sessions from this source, such as `cli`.
    public var source: String?
    /// Profile to prune in.
    public var profile: String?
    /// Title pattern (SQL `LIKE`).
    public var titleLike: String?
    /// Only sessions that ended for this reason.
    public var endReason: String?
    /// Only sessions started in this working directory tree.
    public var cwdPrefix: String?

    /// Creates a filter. An empty one asks the server's default (older than 90 days).
    public init(
        olderThanDays: Double? = nil, source: String? = nil, profile: String? = nil, titleLike: String? = nil,
        endReason: String? = nil, cwdPrefix: String? = nil
    ) {
        self.olderThanDays = olderThanDays
        self.source = source
        self.profile = profile
        self.titleLike = titleLike
        self.endReason = endReason
        self.cwdPrefix = cwdPrefix
    }

    enum CodingKeys: String, CodingKey {
        case source, profile
        case olderThanDays = "older_than_days"
        case titleLike = "title_like"
        case endReason = "end_reason"
        case cwdPrefix = "cwd_prefix"
    }
}

/// The server calls the session library needs. ``RESTClient`` conforms; tests use a fake.
public protocol SessionsBackend: Sendable {
    /// `GET /api/sessions`.
    func sessions(limit: Int, offset: Int, archived: Bool) async throws -> SessionList
    /// `GET /api/sessions/search`.
    func searchSessions(_ text: String, limit: Int) async throws -> SessionSearchResults
    /// `PATCH /api/sessions/{id}`.
    func updateSession(id: String, _ update: SessionUpdate) async throws
    /// `DELETE /api/sessions/{id}`.
    func deleteSession(id: String) async throws
    /// `GET /api/sessions/{id}?profile=`: one session, for a link. A `404` means it is gone.
    func session(id: String, profile: String) async throws -> SessionRecord
    /// `GET /api/sessions/{id}/export`: the session as the server sent it. `profile` is sent only when it is not the
    /// client's own profile.
    func exportSession(id: String, profile: String?) async throws -> Data
    /// `POST /api/sessions/prune`. The answer is left raw: the contract does not describe it.
    func pruneSessions(_ filter: SessionPruneFilter) async throws -> JSONValue
}

extension RESTClient: SessionsBackend {}

/// The count a prune answer reports for the sessions it removed. The contract does not describe the answer, so only a
/// count under a known key is read. Nil means the answer carries none, and the app says "Done" instead.
public enum SessionPruneReport {
    /// The removed count, when the answer has one. A list under one of the keys counts its items.
    public static func removedCount(in answer: JSONValue) -> Int? {
        for key in ["removed", "removed_count", "deleted", "deleted_count", "pruned", "pruned_count"] {
            switch answer[key] {
            case .int(let count)? where count >= 0: return count
            case .array(let items)?: return items.count
            default: continue
            }
        }
        return nil
    }
}

/// The session list of one connection, offline first (WP-40).
///
/// Reads come from the local cache at once and are refreshed from the server. Changes are applied to the cache
/// first, so the list responds instantly, and are undone if the server refuses. The server stays the source of
/// truth: a refresh rewrites what the cache holds.
public actor SessionLibrary {
    private let backend: any SessionsBackend
    private let cache: HermesCache
    private let connection: String
    private let pageSize: Int

    /// Creates the library of one saved connection (`connection` is its id).
    public init(backend: any SessionsBackend, cache: HermesCache, connection: String, pageSize: Int = 50) {
        self.backend = backend
        self.cache = cache
        self.connection = connection
        self.pageSize = pageSize
    }

    /// The cached sessions, pinned first and then newest first. Archived and hidden ones are left out unless asked.
    public func cached(includeArchived: Bool = false, includeHidden: Bool = false) async throws -> [SessionRecord] {
        let all = try await cache.sessions(connection: connection, limit: 1000)
        let shown = all.filter {
            (includeArchived || $0.archived?.value != true) && (includeHidden || $0.hidden?.value != true)
        }
        return shown.filter { $0.pinned?.value == true } + shown.filter { $0.pinned?.value != true }
    }

    /// Fetches the newest page and updates the cache. Sessions deleted elsewhere disappear: all of them when the
    /// page held the whole list, else the ones newer than the oldest session on the page.
    @discardableResult
    public func refresh() async throws -> [SessionRecord] {
        let page = try await backend.sessions(limit: pageSize, offset: 0, archived: false)
        try await cache.saveSessions(page.sessions, connection: connection)
        let listed = Set(page.sessions.map(\.id))
        let wholeList = page.sessions.count >= page.total
        let oldest = page.sessions.compactMap { $0.lastActivityAt ?? $0.startedAt }.min()
        for record in try await cache.sessions(connection: connection, limit: 1000)
        where record.archived?.value != true && !listed.contains(record.id) {
            let activity = record.lastActivityAt ?? record.startedAt ?? 0
            if wholeList || activity > (oldest ?? .infinity) {
                try await cache.removeSession(record.id, connection: connection)
            }
        }
        return try await cached()
    }

    /// Fetches the next page after `loaded` sessions. Returns false when the server has no more.
    public func loadMore(after loaded: Int) async throws -> Bool {
        let page = try await backend.sessions(limit: pageSize, offset: loaded, archived: false)
        try await cache.saveSessions(page.sessions, connection: connection)
        return loaded + page.sessions.count < page.total
    }

    /// Fetches archived sessions into the cache and returns them, newest first.
    public func refreshArchived() async throws -> [SessionRecord] {
        let page = try await backend.sessions(limit: pageSize, offset: 0, archived: true)
        try await cache.saveSessions(page.sessions, connection: connection)
        return try await cache.sessions(connection: connection, limit: 1000).filter { $0.archived?.value == true }
    }

    // MARK: - Changes

    /// Renames a session.
    public func rename(_ id: String, to title: String) async throws {
        try await change(id, SessionUpdate(title: title)) { $0.title = title }
    }

    /// Archives or restores a session.
    public func setArchived(_ id: String, _ archived: Bool) async throws {
        try await change(id, SessionUpdate(archived: archived)) { $0.archived = LooseBool(archived) }
    }

    /// Pins or unpins a session.
    public func setPinned(_ id: String, _ pinned: Bool) async throws {
        try await change(id, SessionUpdate(pinned: pinned)) { $0.pinned = LooseBool(pinned) }
    }

    /// Hides or shows a session.
    public func setHidden(_ id: String, _ hidden: Bool) async throws {
        try await change(id, SessionUpdate(hidden: hidden)) { $0.hidden = LooseBool(hidden) }
    }

    /// Deletes a session on the server, then from the cache. Cannot be undone.
    public func delete(_ id: String) async throws {
        try await backend.deleteSession(id: id)
        try await cache.removeSession(id, connection: connection)
    }

    /// Deletes ended sessions matching `filter`, then refreshes. Cannot be undone.
    public func prune(_ filter: SessionPruneFilter) async throws -> JSONValue {
        let answer = try await backend.pruneSessions(filter)
        // The server has already removed the sessions, so a failed refresh must not report the prune as failed.
        _ = try? await refresh()
        return answer
    }

    /// The session as JSON, for saving or sharing. `profile` is the session's owner and `activeProfile` the profile
    /// this list reads: the owner is sent only when it differs. Throws ``SessionExportError/notJSON`` when the answer
    /// does not parse.
    public func export(_ id: String, profile: String?, activeProfile: String?) async throws -> Data {
        let other = profile == activeProfile ? nil : profile
        let data = try await backend.exportSession(id: id, profile: other)
        guard SessionExport.isJSON(data) else { throw SessionExportError.notJSON }
        return data
    }

    /// Fetches one session, such as one an `@session:` link names, and keeps it in the cache so the list shows it.
    /// Throws ``RESTError/http(status:detail:)`` with `404` when the server no longer has it.
    public func fetch(_ reference: SessionReference) async throws -> SessionRecord {
        let record = try await backend.session(id: reference.sessionID, profile: reference.profile)
        try await cache.saveSessions([record], connection: connection)
        return record
    }

    // MARK: - Search

    /// Searches message text on the server. Offline, it falls back to titles and ids in the cache.
    public func search(_ text: String) async throws -> [SessionSearchHit] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        do {
            return try await backend.searchSessions(query, limit: 30).results
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await searchLocally(query)
        }
    }

    private func searchLocally(_ query: String) async throws -> [SessionSearchHit] {
        try await cached(includeArchived: true).filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }.map {
            SessionSearchHit(
                sessionId: $0.id, snippet: nil, role: nil, title: $0.title, source: $0.source, model: $0.model,
                lastActive: $0.lastActivityAt, preview: nil)
        }
    }

    // MARK: - Optimistic change

    private func change(_ id: String, _ update: SessionUpdate, apply: (inout SessionRecord) -> Void) async throws {
        let original = try await cache.sessions(connection: connection, limit: 1000).first { $0.id == id }
        if var edited = original {
            apply(&edited)
            try await cache.saveSessions([edited], connection: connection)
        }
        do {
            try await backend.updateSession(id: id, update)
        } catch {
            if let original { try? await cache.saveSessions([original], connection: connection) }
            throw error
        }
    }
}
