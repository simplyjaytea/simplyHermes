import Foundation
import Testing

/// WP-53/54/55 CI gate for `Fixtures/rest/index.json`, written by `testbed/tools/record_rest.py`. A recorded entry names
/// a file that holds `step`, `request`, `status` and `body`, and the file agrees with its entry. A skipped entry has no
/// file and gives the reason it was not sent.
@Suite struct RESTFixtureTests {
    private static let directory = FixtureFiles.directory.appendingPathComponent("rest")

    private static func object(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func indexNamesTheRecorderAndAPinnedUpstreamCommit() throws {
        let index = try Self.object(at: Self.directory.appendingPathComponent("index.json"))
        #expect(index["recorder"] as? String == "testbed/tools/record_rest.py")
        let upstream = try #require(index["upstream"] as? String)
        #expect(upstream.count == 40 && upstream.allSatisfy(\.isHexDigit))
        #expect(index["entries"] is [Any])
    }

    @Test func everyEntryIsSkippedWithAReasonOrPointsAtAMatchingAnswerFile() throws {
        let index = try Self.object(at: Self.directory.appendingPathComponent("index.json"))
        let entries = try #require(index["entries"] as? [[String: Any]])
        for entry in entries {
            let label = "\(entry["method"] as? String ?? "?") \(entry["path"] as? String ?? "?")"
            if let reason = entry["skipped"] as? String {
                #expect(!reason.isEmpty, "\(label) is skipped without a reason")
                #expect(entry["file"] is NSNull, "\(label) is skipped but names a file")
                continue
            }
            let name = try #require(entry["file"] as? String, "\(label) has neither a file nor a skip reason")
            let url = Self.directory.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(name) is listed in index.json but missing")
            let answer = try Self.object(at: url)
            for key in ["step", "request", "status", "body"] {
                #expect(answer[key] != nil, "\(name) has no '\(key)' key")
            }
            #expect(answer["step"] as? String == entry["step"] as? String, "\(name): step differs from index.json")
            #expect(answer["status"] as? Int == entry["status"] as? Int, "\(name): status differs from index.json")
            let request = answer["request"] as? [String: Any]
            #expect(request?["method"] as? String == entry["method"] as? String, "\(name): method differs")
            #expect(request?["path"] as? String == entry["path"] as? String, "\(name): path differs")
        }
    }

    @Test func everyRecorderFileIsListedInTheIndex() throws {
        let index = try Self.object(at: Self.directory.appendingPathComponent("index.json"))
        let entries = index["entries"] as? [[String: Any]] ?? []
        let listed = Set(entries.compactMap { $0["file"] as? String })
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
        for name in names where name.range(of: #"^(GET|POST|PUT|PATCH|DELETE)_"#, options: .regularExpression) != nil {
            #expect(listed.contains(name), "\(name) is not listed in index.json")
        }
    }
}
