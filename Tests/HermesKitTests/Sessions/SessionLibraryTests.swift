import Foundation
import HermesKit
import Testing

private func record(_ id: String, _ time: Double, title: String? = nil, extra: String = "") throws -> SessionRecord {
    let titleJSON = title.map { #","title":"\#($0)""# } ?? ""
    let json = #"{"id":"\#(id)","lastActivityAt":\#(time)\#(titleJSON)\#(extra)}"#
    return try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
}

private final class FakeBackend: SessionsBackend, @unchecked Sendable {
    private let lock = NSLock()
    var pages: [SessionList] = []
    var archivedPage: SessionList?
    var failUpdates = false
    var failSearch = false
    private(set) var updates: [(String, SessionUpdate)] = []
    private(set) var deleted: [String] = []
    private(set) var pruned: [SessionPruneFilter] = []
    private(set) var requestedOffsets: [Int] = []
    var failListing = false
    var exportAnswer = Data(#"{"id":"a"}"#.utf8)
    private(set) var exported: [(id: String, profile: String?)] = []
    var sessionsByID: [String: SessionRecord] = [:]
    private(set) var lookedUp: [(id: String, profile: String)] = []

    func sessions(limit: Int, offset: Int, archived: Bool) async throws -> SessionList {
        if failListing { throw RESTError.transport("offline") }
        return try lock.withLock {
            requestedOffsets.append(offset)
            if archived, let archivedPage { return archivedPage }
            return pages.isEmpty ? try SessionList.make([], total: 0) : pages.removeFirst()
        }
    }

    func searchSessions(_ text: String, limit: Int) async throws -> SessionSearchResults {
        if failSearch { throw RESTError.transport("offline") }
        return try JSONDecoder().decode(
            SessionSearchResults.self, from: Data(#"{"results":[{"sessionId":"srv","snippet":">>>\#(text)<<<"}]}"#.utf8)
        )
    }

    func updateSession(id: String, _ update: SessionUpdate) async throws {
        if failUpdates { throw RESTError.transport("refused") }
        lock.withLock { updates.append((id, update)) }
    }

    func deleteSession(id: String) async throws { lock.withLock { deleted.append(id) } }

    func session(id: String, profile: String) async throws -> SessionRecord {
        lock.withLock { lookedUp.append((id, profile)) }
        guard let record = sessionsByID[id] else { throw RESTError.http(status: 404, detail: "Session not found") }
        return record
    }

    func exportSession(id: String, profile: String?) async throws -> Data {
        lock.withLock { exported.append((id, profile)) }
        return exportAnswer
    }

    func pruneSessions(_ filter: SessionPruneFilter) async throws -> JSONValue {
        lock.withLock { pruned.append(filter) }
        return .object(["deleted": .int(2)])
    }
}

extension SessionList {
    fileprivate static func make(_ sessions: [SessionRecord], total: Int) throws -> SessionList {
        let data = try JSONEncoder().encode(sessions)
        let json = #"{"sessions":\#(String(bytes: data, encoding: .utf8) ?? ""),"total":\#(total)}"#
        return try JSONDecoder().decode(SessionList.self, from: Data(json.utf8))
    }
}

private func library(_ backend: FakeBackend) throws -> SessionLibrary {
    SessionLibrary(backend: backend, cache: try HermesCache(), connection: "x", pageSize: 2)
}

@Suite struct SessionLibraryTests {
    @Test func refreshFillsTheCacheAndOfflineReadsStillWork() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("b", 20), try record("a", 10)], total: 2)]
        let lib = try library(backend)
        #expect(try await lib.cached().isEmpty)
        #expect(try await lib.refresh().map(\.id) == ["b", "a"])
        backend.pages = []
        #expect(try await lib.cached().map(\.id) == ["b", "a"], "cache serves without the server")
    }

    @Test func pinnedSessionsComeFirst() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("new", 30), try record("old", 10, extra: #","pinned":1"#)], total: 2)]
        let lib = try library(backend)
        #expect(try await lib.refresh().map(\.id) == ["old", "new"])
    }

    @Test func refreshDropsSessionsDeletedElsewhere() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("c", 30), try record("b", 20)], total: 3),
            try .make([try record("a", 10)], total: 3),
            try .make([try record("c", 30), try record("a", 10)], total: 2),
        ]
        let lib = try library(backend)
        _ = try await lib.refresh()
        _ = try await lib.loadMore(after: 2)
        #expect(try await lib.cached().map(\.id) == ["c", "b", "a"])
        #expect(try await lib.refresh().map(\.id) == ["c", "a"], "b is gone and the page held the whole list")
    }

    @Test func partialPageOnlyDropsSessionsNewerThanItsOldest() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("d", 40), try record("c", 30)], total: 4),
            try .make([try record("b", 20), try record("a", 10)], total: 4),
            try .make([try record("d", 40), try record("e", 50)], total: 4),
        ]
        let lib = try library(backend)
        _ = try await lib.refresh()
        _ = try await lib.loadMore(after: 2)
        // New page lists d and e only (total says there are more): c at 30 is below 40, so it stays; nothing newer is missing.
        #expect(Set(try await lib.refresh().map(\.id)) == ["a", "b", "c", "d", "e"])
    }

    @Test func partialPageDropsAMissingSessionNewerThanItsOldest() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("d", 40), try record("c", 30)], total: 4),
            try .make([try record("c", 30), try record("b", 20)], total: 4),
        ]
        let lib = try library(backend)
        _ = try await lib.refresh()
        #expect(
            try await lib.refresh().map(\.id) == ["c", "b"], "d is newer than the page's oldest and was not listed")
    }

    @Test func archivedSessionsAreNotRemovedByARefresh() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("b", 20), try record("a", 10)], total: 2),
            try .make([try record("b", 20)], total: 1),
        ]
        let lib = try library(backend)
        _ = try await lib.refresh()
        try await lib.setArchived("a", true)
        #expect(try await lib.refresh().map(\.id) == ["b"])
        #expect(try await lib.cached(includeArchived: true).map(\.id) == ["b", "a"])
    }

    @Test func loadMoreReportsWhetherThereIsMore() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("a", 1), try record("b", 2)], total: 3), try .make([try record("c", 0)], total: 3),
        ]
        let lib = try library(backend)
        #expect(try await lib.loadMore(after: 0) == true)
        #expect(try await lib.loadMore(after: 2) == false)
        #expect(backend.requestedOffsets == [0, 2])
    }

    @Test func changesApplyAtOnceAndReachTheServer() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("a", 10, title: "Old")], total: 1)]
        let lib = try library(backend)
        _ = try await lib.refresh()
        try await lib.rename("a", to: "New")
        try await lib.setPinned("a", true)
        let shown = try await lib.cached().first
        #expect(shown?.title == "New" && shown?.pinned?.value == true)
        #expect(backend.updates.map(\.0) == ["a", "a"])
        #expect(backend.updates.first?.1 == SessionUpdate(title: "New"))
    }

    @Test func aRefusedChangeIsUndone() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("a", 10, title: "Old")], total: 1)]
        let lib = try library(backend)
        _ = try await lib.refresh()
        backend.failUpdates = true
        await #expect(throws: RESTError.self) { try await lib.rename("a", to: "New") }
        #expect(try await lib.cached().first?.title == "Old")
    }

    @Test func hiddenSessionsAreOnlyShownOnRequest() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("a", 10), try record("h", 5, extra: #","hidden":true"#)], total: 2)]
        let lib = try library(backend)
        #expect(try await lib.refresh().map(\.id) == ["a"])
        #expect(try await lib.cached(includeHidden: true).map(\.id) == ["a", "h"])
    }

    @Test func deleteGoesToTheServerThenTheCache() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("a", 10)], total: 1)]
        let lib = try library(backend)
        _ = try await lib.refresh()
        try await lib.delete("a")
        #expect(backend.deleted == ["a"])
        #expect(try await lib.cached().isEmpty)
    }

    @Test func searchUsesTheServerAndFallsBackToTitlesOffline() async throws {
        let backend = FakeBackend()
        backend.pages = [
            try .make([try record("a", 10, title: "Deploy script"), try record("b", 5, title: "Notes")], total: 2)
        ]
        let lib = try library(backend)
        _ = try await lib.refresh()
        #expect(try await lib.search("deploy").map(\.sessionId) == ["srv"])
        backend.failSearch = true
        #expect(try await lib.search("deploy").map(\.sessionId) == ["a"])
        #expect(try await lib.search("  ").isEmpty)
    }

    @Test func pruneSendsTheFilterAndRefreshes() async throws {
        let backend = FakeBackend()
        backend.pages = [try .make([try record("a", 10)], total: 1)]
        let lib = try library(backend)
        let answer = try await lib.prune(SessionPruneFilter(olderThanDays: 30, source: "cli"))
        #expect(answer["deleted"] == .int(2))
        #expect(backend.pruned.first?.olderThanDays == 30 && backend.pruned.first?.source == "cli")
        #expect(try await lib.cached().map(\.id) == ["a"])
    }

    @Test func pruneFilterEncodesWireKeysAndOmitsUnset() throws {
        let json = try JSONValue(encoding: SessionPruneFilter(olderThanDays: 7, titleLike: "tmp%"))
        #expect(json["older_than_days"] == .int(7) && json["title_like"] == .string("tmp%"))
        #expect(json["source"] == nil && json["profile"] == nil)
    }

    @Test func exportReturnsTheServersJSON() async throws {
        let backend = FakeBackend()
        let lib = try library(backend)
        let data = try await lib.export("a", profile: "default", activeProfile: "default")
        #expect(String(bytes: data, encoding: .utf8) == #"{"id":"a"}"#)
        #expect(backend.exported.first?.profile == nil, "the active profile is the client's own: no profile sent")
    }

    @Test func exportNamesTheOwnerOnlyWhenItIsAnotherProfile() async throws {
        let backend = FakeBackend()
        let lib = try library(backend)
        _ = try await lib.export("a", profile: "ops", activeProfile: "default")
        _ = try await lib.export("b", profile: nil, activeProfile: "default")
        #expect(backend.exported.map(\.profile) == ["ops", nil])
    }

    @Test func exportRefusesAnAnswerThatIsNotJSON() async throws {
        let backend = FakeBackend()
        backend.exportAnswer = Data("<html>Sign in</html>".utf8)
        let lib = try library(backend)
        await #expect(throws: SessionExportError.notJSON) {
            try await lib.export("a", profile: nil, activeProfile: nil)
        }
    }

    @Test func fetchKeepsTheSessionInTheCache() async throws {
        let backend = FakeBackend()
        backend.sessionsByID["ops-1"] = try record("ops-1", 5, title: "Deploy")
        let lib = try library(backend)
        let fetched = try await lib.fetch(SessionReference(profile: "ops", sessionID: "ops-1"))
        #expect(fetched.title == "Deploy")
        #expect(backend.lookedUp.first?.profile == "ops")
        #expect(try await lib.cached().map(\.id) == ["ops-1"])
    }

    @Test func fetchOfAGoneSessionReportsNotFound() async throws {
        let lib = try library(FakeBackend())
        await #expect(throws: RESTError.http(status: 404, detail: "Session not found")) {
            try await lib.fetch(SessionReference(profile: "ops", sessionID: "gone"))
        }
    }

    @Test func aPruneThatRemovedSessionsStillSucceedsWhenTheRefreshFails() async throws {
        let backend = FakeBackend()
        let lib = try library(backend)
        backend.failListing = true
        let answer = try await lib.prune(SessionPruneFilter(olderThanDays: 90, profile: "default"))
        #expect(answer == .object(["deleted": .int(2)]))
        #expect(backend.pruned.first?.profile == "default")
    }

    @Test func pruneReportReadsOnlyAKnownCount() {
        #expect(SessionPruneReport.removedCount(in: .object(["deleted": .int(2)])) == 2)
        #expect(SessionPruneReport.removedCount(in: .object(["removed_count": .int(0)])) == 0)
        #expect(SessionPruneReport.removedCount(in: .object(["removed": .array([.string("a")])])) == 1)
        #expect(SessionPruneReport.removedCount(in: .object(["ok": .bool(true)])) == nil)
        #expect(SessionPruneReport.removedCount(in: .object(["deleted": .int(-1)])) == nil)
        #expect(SessionPruneReport.removedCount(in: .null) == nil)
    }
}
