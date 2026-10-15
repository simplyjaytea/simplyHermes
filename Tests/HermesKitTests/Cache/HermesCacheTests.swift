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

/// Loading the newest page of a 10k-message transcript must stay fast. The baseline is the median on the CI runner;
/// the test fails on a regression over 20%. `HERMES_CACHE_BASELINE_MS` overrides it for slower machines.
@Test func loadingATenThousandMessageTranscriptStaysWithinBaseline() async throws {
    let cache = try HermesCache()
    let body = String(repeating: "lorem ipsum dolor sit amet ", count: 40)
    try await cache.saveMessages((1...10_000).map { try message($0, text: body) }, connection: "x")

    var samples: [Double] = []
    for _ in 0..<7 {
        let start = ContinuousClock.now
        let page = try await cache.messages(sessionID: "s1", connection: "x", limit: 10_000)
        let elapsed = ContinuousClock.now - start
        #expect(page.count == 10_000)
        samples.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    let median = samples.sorted()[samples.count / 2]
    let baseline = ProcessInfo.processInfo.environment["HERMES_CACHE_BASELINE_MS"].flatMap(Double.init) ?? 250
    print("cache load of 10k messages: median \(median) ms, baseline \(baseline) ms")
    #expect(median <= baseline * 1.2, "10k load took \(median) ms, baseline \(baseline) ms")
}
