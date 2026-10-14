import Foundation
import Testing

/// WP-01 CI gate: every recorded fixture is valid JSON-RPC, and every method, event and
/// server request the client depends on (`docs/protocol/coverage.json`) appears in at least
/// one fixture, or is listed with a reason under `gaps`.
private let repoRoot: URL = {
    // Tests/HermesKitTests/FixtureLintTests.swift -> repo root
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}()

private struct FixtureLine {
    let name: String
    let dir: String
    let frame: [String: Any]
}

private func loadFixtures() throws -> [FixtureLine] {
    let dir = repoRoot.appendingPathComponent("Fixtures")
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasSuffix(".jsonl") }.sorted()
    var out: [FixtureLine] = []
    for file in files {
        let text = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
        for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let obj = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                let dirValue = obj["dir"] as? String,
                let frame = obj["frame"] as? [String: Any]
            else {
                Issue.record("\(file):\(n + 1) is not a {dir, frame} line")
                continue
            }
            out.append(FixtureLine(name: file, dir: dirValue, frame: frame))
        }
    }
    return out
}

private func isValidJSONRPC(_ frame: [String: Any]) -> Bool {
    guard (frame["jsonrpc"] as? String) == "2.0" else { return false }
    let hasMethod = frame["method"] is String
    let hasID = frame["id"] != nil
    let hasResult = frame["result"] != nil
    let hasError = frame["error"] != nil
    if hasMethod { return true }  // request or notification
    return hasID && (hasResult != hasError)  // response
}

@Test func fixturesExistAndAreValidJSONRPC() throws {
    let lines = try loadFixtures()
    #expect(lines.count > 100)
    for line in lines where !isValidJSONRPC(line.frame) {
        Issue.record("\(line.name): not valid JSON-RPC 2.0: \(line.frame)")
    }
}

@Test func everyRequiredMethodEventAndServerRequestHasAFixture() throws {
    let lines = try loadFixtures()
    var methodsSent = Set<String>()
    var events = Set<String>()
    var serverRequests = Set<String>()
    for line in lines {
        guard let method = line.frame["method"] as? String else { continue }
        if line.dir == "out" {
            methodsSent.insert(method)
        } else if method == "event", let params = line.frame["params"] as? [String: Any],
            let type = params["type"] as? String
        {
            events.insert(type)
        } else if line.frame["id"] != nil {
            serverRequests.insert(method)
        }
    }
    let data = try Data(contentsOf: repoRoot.appendingPathComponent("docs/protocol/coverage.json"))
    let coverage = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    func check(_ key: String, _ seen: Set<String>) throws {
        let section = try #require(coverage[key] as? [String: Any])
        let required = try #require(section["required"] as? [String])
        let gaps = (section["gaps"] as? [String: String]) ?? [:]
        for name in required where !seen.contains(name) && gaps[name] == nil {
            Issue.record("\(key): '\(name)' has no fixture and no entry under gaps")
        }
        for (name, reason) in gaps where seen.contains(name) {
            Issue.record("\(key): '\(name)' is listed as a gap (\(reason)) but now has a fixture; remove the gap")
        }
        for (name, reason) in gaps {
            #expect(!reason.isEmpty, "\(key): gap '\(name)' needs a reason")
        }
    }
    try check("methods", methodsSent)
    try check("events", events)
    try check("server_requests", serverRequests)
}
