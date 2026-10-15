import Foundation
import HermesKit
import Testing

private func record(_ id: String, _ activity: Double, title: String? = nil, extra: String = "") throws -> SessionRecord
{
    let titleJSON = title.map { #","title":"\#($0)""# } ?? ""
    let json = #"{"id":"\#(id)","lastActivityAt":\#(activity)\#(titleJSON)\#(extra)}"#
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

    func sessions(limit: Int, offset: Int, archived: Bool) async throws -> SessionList {
        try lock.withLock {
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
    func exportSession(id: String) async throws -> Data { Data("{\"id\":\"\(id)\"}".utf8) }

    func pruneSessions(_ filter: SessionPruneFilter) async throws -> JSONValue {
        lock.withLock { pruned.append(filter) }
        return .object(["deleted": .int(2)])
    }
}

extension SessionList {
    fileprivate static func make(_ sessions: [SessionRecord], total: Int) throws -> SessionList {
        let data = try JSONEncoder().encode(sessions)
        let json = #"{"sessions":\#(String(decoding: data, as: UTF8.self)),"total":\#(total)}"#
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
        let lib = try library(FakeBackend())
        #expect(String(decoding: try await lib.export("a"), as: UTF8.self) == #"{"id":"a"}"#)
    }
}
