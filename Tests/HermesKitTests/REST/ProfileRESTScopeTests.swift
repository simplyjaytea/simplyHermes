import Foundation
import HermesKit
import Testing

/// One REST operation whose OpenAPI parameters take a `profile` query.
private struct ProfileOperation: Sendable {
    var method: String
    var path: String
}

/// Every operation of docs/protocol/dashboard-openapi.json that declares a `profile` query, on the operation or on its
/// path item.
private func profileOperations() throws -> [ProfileOperation] {
    let spec = FixtureFiles.directory.deletingLastPathComponent()
        .appendingPathComponent("docs/protocol/dashboard-openapi.json")
    let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: spec)) as? [String: Any])
    let paths = try #require(root["paths"] as? [String: Any])
    var found: [ProfileOperation] = []
    for (path, value) in paths {
        guard let item = value as? [String: Any] else { continue }
        let shared = item["parameters"] as? [[String: Any]] ?? []
        for method in ["get", "put", "post", "delete", "patch"] {
            guard let operation = item[method] as? [String: Any] else { continue }
            let own = operation["parameters"] as? [[String: Any]] ?? []
            let takesProfile = (shared + own).contains {
                $0["name"] as? String == "profile" && $0["in"] as? String == "query"
            }
            if takesProfile { found.append(ProfileOperation(method: method.uppercased(), path: path)) }
        }
    }
    return found.sorted { $0.path == $1.path ? $0.method < $1.method : $0.path < $1.path }
}

/// A template path with each `{parameter}` replaced by a placeholder, so a call can be built from it.
private func concretePath(_ template: String) -> String {
    var result = ""
    var inBrace = false
    for character in template {
        if character == "{" {
            inBrace = true
            result += "x"
        } else if character == "}" {
            inBrace = false
        } else if !inBrace {
            result.append(character)
        }
    }
    return result
}

/// The REST half of the profile guard. `ProfileScopeTests` guards the RPC list the same way.
@Suite struct ProfileRESTScopeTests {
    @Test func theSpecListsTheProfileOperations() throws {
        let operations = try profileOperations()
        #expect(operations.count >= 100, "the walk below must not pass because it read nothing")
        #expect(operations.contains { $0.method == "GET" && $0.path == "/api/sessions" })
        #expect(operations.contains { $0.method == "PUT" && $0.path == "/api/config" })
    }

    /// CI gate: a client scoped to a profile sends it on every operation the OpenAPI says takes one.
    @Test func everyProfileOperationCarriesTheActiveProfile() async throws {
        for operation in try profileOperations() {
            let http = FakeHTTP()
            http.enqueue(200, "{}")
            let client = makeClient(http, profile: "ops")
            _ = try await client.sendRaw(operation.method, concretePath(operation.path))
            let query = try #require(http.requests.first).url.query
            #expect(query?.contains("profile=ops") == true, "\(operation.method) \(operation.path) sent no profile")
        }
    }

    /// CI gate: a call that skips the active profile on an operation that takes one must be written down here with a
    /// reason. The calls are read from Sources/HermesKit/REST the way `ProfileScopeTests` reads them.
    @Test func unscopedCallsOnProfileOperationsAreDocumented() throws {
        let documented: [String: String] = [
            "/api/status":
                "the connection check and sign-in read it before a profile is chosen. The spec says its ?profile= "
                + "is the dashboard switcher's config-only scope."
        ]
        // Templated operations are matched by the static part before the first `{`, which is what a call concatenates.
        let takesProfile = Set(try profileOperations().map { String($0.path.split(separator: "{").first ?? "") })
        let sources = FixtureFiles.directory.deletingLastPathComponent()
            .appendingPathComponent("Sources/HermesKit/REST")
        var unscopedCalls = 0
        var problems: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let chunks = text.components(separatedBy: "\n\n").flatMap { $0.components(separatedBy: "\n    }") }
            for chunk in chunks where chunk.contains("scoped: false") {
                unscopedCalls += 1
                for literal in chunk.split(separator: "\"").map(String.init) where literal.hasPrefix("/") {
                    if takesProfile.contains(literal), documented[literal] == nil {
                        problems.append("\(file): \(literal)")
                    }
                }
            }
        }
        #expect(unscopedCalls >= 10, "the scan must see the unscoped calls, or it proves nothing")
        #expect(problems.isEmpty, "unscoped calls on profile operations without a reason: \(problems)")
    }
}
