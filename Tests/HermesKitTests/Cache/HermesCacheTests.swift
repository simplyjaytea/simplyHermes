import Foundation
import HermesKit
import Testing

private func session(_ id: String, activity: Double) throws -> SessionRecord {
    let json = #"{"id":"\#(id)","title":"Title \#(id)","lastActivityAt":\#(activity)}"#
    return try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
}

private func message(_ rowID: Int, session: String = "s1", text: String? = nil) throws -> StoredMessage {
    let content = text ?? "message \(rowID)"
    let json = #"{"id":\#(rowID),"sessionId":"\#(session)","role":"user","content":"\#(content)"}"#
    return try JSONDecoder().decode(StoredMessage.self, from: Data(json.utf8))
}

// MARK: - Sessions

@Test func sessionsComeBackNewestFirst() async throws {
    let cache = try HermesCache()
    try await cache.saveSessions(
        [session("a", activity: 10), session("b", activity: 30), session("c", activity: 20)], connection: "x")
    #expect(try await cache.sessions(connection: "x").map(\.id) == ["b", "c", "a"])
    #expect(try await cache.sessions(connection: "x", limit: 2).map(\.id) == ["b", "c"])
}

@Test func savingASessionAgainUpdatesIt() async throws {
    let cache = try HermesCache()
    try await cache.saveSessions([session("a", activity: 10), session("b", activity: 20)], connection: "x")
    try await cache.saveSessions([session("a", activity: 99)], connection: "x")
    let sessions = try await cache.sessions(connection: "x")
    #expect(sessions.map(\.id) == ["a", "b"])
    #expect(sessions.first?.lastActivityAt == 99)
}

@Test func removingASessionRemovesItsMessagesAndPosition() async throws {
    let cache = try HermesCache()
    try await cache.saveSessions([session("s1", activity: 1)], connection: "x")
    try await cache.saveMessages([message(1)], connection: "x")
    try await cache.setReadingPosition(ReadingPosition(anchorItemID: "row-1"), sessionID: "s1", connection: "x")
    try await cache.removeSession("s1", connection: "x")
    #expect(try await cache.sessions(connection: "x").isEmpty)
    #expect(try await cache.messageCount(sessionID: "s1", connection: "x") == 0)
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "x") == nil)
}

// MARK: - Messages

@Test func messagesPageBackwardsFromTheNewest() async throws {
    let cache = try HermesCache()
    try await cache.saveMessages((1...10).map { try message($0) }, connection: "x")
    let newest = try await cache.messages(sessionID: "s1", connection: "x", limit: 4)
    #expect(newest.map(\.id) == [7, 8, 9, 10])
    let older = try await cache.messages(sessionID: "s1", connection: "x", beforeRowID: 7, limit: 4)
    #expect(older.map(\.id) == [3, 4, 5, 6])
    let oldest = try await cache.messages(sessionID: "s1", connection: "x", beforeRowID: 3, limit: 4)
    #expect(oldest.map(\.id) == [1, 2])
}

@Test func savingAMessageAgainReplacesItsContent() async throws {
    let cache = try HermesCache()
    try await cache.saveMessages([message(1, text: "draft")], connection: "x")
    try await cache.saveMessages([message(1, text: "final")], connection: "x")
    let stored = try await cache.messages(sessionID: "s1", connection: "x")
    #expect(stored.map(\.content) == ["final"])
}

@Test func sessionsKeepTheirOwnMessages() async throws {
    let cache = try HermesCache()
    try await cache.saveMessages([message(1), message(2, session: "s2")], connection: "x")
    #expect(try await cache.messageCount(sessionID: "s1", connection: "x") == 1)
    #expect(try await cache.messageCount(sessionID: "s2", connection: "x") == 1)
}

@Test func rewindDropsMessagesFromTheCutOn() async throws {
    let cache = try HermesCache()
    try await cache.saveMessages((1...6).map { try message($0) }, connection: "x")
    try await cache.removeMessages(sessionID: "s1", connection: "x", fromRowID: 4)
    #expect(try await cache.messages(sessionID: "s1", connection: "x").map(\.id) == [1, 2, 3])
}

@Test func replaceSwapsTheWholeHistory() async throws {
    let cache = try HermesCache()
    try await cache.saveMessages((1...5).map { try message($0) }, connection: "x")
    try await cache.replaceMessages([message(20), message(21)], sessionID: "s1", connection: "x")
    #expect(try await cache.messages(sessionID: "s1", connection: "x").map(\.id) == [20, 21])
}

// MARK: - Reading position

@Test func readingPositionRoundTripsAndOverwrites() async throws {
    let cache = try HermesCache()
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "x") == nil)
    let first = ReadingPosition(
        anchorItemID: "row-5", anchorRowID: 5, offset: 12.5, atBottom: false,
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    try await cache.setReadingPosition(first, sessionID: "s1", connection: "x")
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "x") == first)
    let second = ReadingPosition(
        anchorItemID: "row-9", atBottom: true, updatedAt: Date(timeIntervalSince1970: 1_800_000_100))
    try await cache.setReadingPosition(second, sessionID: "s1", connection: "x")
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "x") == second)
}

// MARK: - Connections and files

@Test func connectionsNeverMixAndPurgeClearsOnlyOne() async throws {
    let cache = try HermesCache()
    for connection in ["x", "y"] {
        try await cache.saveSessions([session("s1", activity: 1)], connection: connection)
        try await cache.saveMessages([message(1)], connection: connection)
        try await cache.setReadingPosition(
            ReadingPosition(anchorItemID: "row-1"), sessionID: "s1", connection: connection)
    }
    try await cache.purge(connection: "x")
    #expect(try await cache.sessions(connection: "x").isEmpty)
    #expect(try await cache.messageCount(sessionID: "s1", connection: "x") == 0)
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "x") == nil)
    #expect(try await cache.sessions(connection: "y").count == 1)
    #expect(try await cache.messageCount(sessionID: "s1", connection: "y") == 1)
    #expect(try await cache.readingPosition(sessionID: "s1", connection: "y") != nil)
}

@Test func fileCacheSurvivesReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("nested/hermes.sqlite")
    do {
        let cache = try HermesCache(url: url)
        try await cache.saveMessages([message(1), message(2)], connection: "x")
    }
    let reopened = try HermesCache(url: url)
    #expect(try await reopened.messages(sessionID: "s1", connection: "x").map(\.id) == [1, 2])
}

// MARK: - Performance

/// Loading a 10k-message transcript must stay fast, without failing because the machine is busy (row 83).
///
/// - Always checked: 10k messages load in at most `scalingLimit` times the time of 1k, so a missing index or
///   quadratic code fails here. The two loads are interleaved and compared by their fastest runs, so sustained host
///   load slows both alike and does not fail the test.
/// - Checked on CI (`CI` set): the fastest 10k load is within 20% of the baseline, 250 ms, a ceiling of 300 ms. Shared
///   developer machines report it without failing. `HERMES_CACHE_BASELINE_MS` overrides the baseline.
@Test func loadingATenThousandMessageTranscriptStaysWithinBaseline() async throws {
    let cache = try HermesCache()
    let body = String(repeating: "lorem ipsum dolor sit amet ", count: 40)
    try await cache.saveMessages((1...10_000).map { try message($0, text: body) }, connection: "x")
    try await cache.saveMessages(
        (10_001...11_000).map { try message($0, session: "s2", text: body) }, connection: "x")

    func timed(_ session: String, _ count: Int) async throws -> Double {
        let start = ContinuousClock.now
        let page = try await cache.messages(sessionID: session, connection: "x", limit: count)
        let elapsed = ContinuousClock.now - start
        #expect(page.count == count)
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
    var large: [Double] = []
    var small: [Double] = []
    for _ in 0..<9 {
        large.append(try await timed("s1", 10_000))
        small.append(try await timed("s2", 1_000))
    }
    let fastestLarge = large.min() ?? 0
    let fastestSmall = max(small.min() ?? 0, 0.001)
    let scaling = fastestLarge / fastestSmall
    let baseline = ProcessInfo.processInfo.environment["HERMES_CACHE_BASELINE_MS"].flatMap(Double.init) ?? 250
    print(
        "cache load: 10k fastest \(fastestLarge) ms (median \(large.sorted()[4])), 1k fastest \(fastestSmall) ms, "
            + "scaling \(scaling)x, baseline \(baseline) ms")

    #expect(scaling <= cacheScalingLimit, "10k took \(scaling)x the time of 1k: more than linear")
    if ProcessInfo.processInfo.environment["CI"] != nil {
        #expect(fastestLarge <= baseline * 1.2, "10k load took \(fastestLarge) ms, baseline \(baseline) ms")
    }
}

/// Ten times the rows take about ten times as long (9.6x idle on Linux; 7.0x and 13.5x under six busy cores). Twice
/// linear still passes; quadratic code (about 100x) fails.
private let cacheScalingLimit = 20.0
