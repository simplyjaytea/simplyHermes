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

/// The operations the guard lets skip the active profile, with the reason. Each one also needs a real call in
/// Sources/HermesKit/REST that passes `scoped: false`, so a reason cannot outlive its code.
private let documentedExemptions: [String: String] = [
    "/api/status":
        "the public probe. The connection check and sign-in read it before a profile is chosen. The spec's ?profile= "
        + "is the dashboard switcher's config-only scope, which the phone does not use.",
    "/api/profiles/sessions":
        "the list across every profile. The spec's profile query defaults to all, so the active profile would narrow it.",
]

/// The REST half of the profile guard. `ProfileScopeTests` guards the RPC list the same way.
///
/// The spec-driven tests check the contract. The call-site tests check the code the app ships.
@Suite struct ProfileRESTScopeTests {
    /// CI gate: an operation that starts taking a profile fails here until the guard has been reviewed for it.
    @Test func theSpecListsTheProfileOperations() throws {
        let operations = try profileOperations()
        #expect(operations.count == 223, "the guard was reviewed for 223 operations; a new one needs a look")
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

    /// CI gate: the app's own calls, made through the real methods on a client scoped to `ops`. The status probe and the
    /// cross-profile list are the documented exceptions and send no profile. Sessions carries it. The roster is
    /// `profiles()`, which the spec does not scope.
    @Test func realCallsCarryTheProfileExceptTheDocumentedOnes() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, try restFixture("sessions"))
        http.enqueue(200, try restFixture("profiles"))
        http.enqueue(200, "{}")
        let client = makeClient(http, profile: "ops")
        _ = try await client.status()
        _ = try await client.sessions()
        _ = try await client.profiles()
        _ = try await client.sessionsAcrossProfiles()
        let requests = http.requests
        try #require(requests.count == 4)
        #expect(requests[0].url.query == nil, "the status probe takes no profile")
        #expect(requests[1].url.query?.contains("profile=ops") == true, "sessions carries the active profile")
        #expect(requests[2].url.query == nil, "the roster is not a profile operation")
        #expect(requests[3].url.query == nil, "sessions across every profile must not be narrowed")
    }

    /// CI gate: a call that skips the active profile on an operation that takes one must be documented here with a
    /// reason, and each documented reason must have such a call. The calls are read from Sources/HermesKit/REST the way
    /// `ProfileScopeTests` reads them.
    @Test func unscopedCallsOnProfileOperationsAreDocumented() throws {
        // Templated operations are matched by the static part before the first `{`, which is what a call concatenates.
        let takesProfile = Set(try profileOperations().map { String($0.path.split(separator: "{").first ?? "") })
        let sources = FixtureFiles.directory.deletingLastPathComponent()
            .appendingPathComponent("Sources/HermesKit/REST")
        var unscopedCalls = 0
        var problems: [String] = []
        var exempted: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            let chunks = text.components(separatedBy: "\n\n").flatMap { $0.components(separatedBy: "\n    }") }
            for chunk in chunks where chunk.contains("scoped: false") {
                unscopedCalls += 1
                for literal in chunk.split(separator: "\"").map(String.init) where literal.hasPrefix("/") {
                    guard takesProfile.contains(literal) else { continue }
                    if documentedExemptions[literal] == nil {
                        problems.append("\(file): \(literal)")
                    } else {
                        exempted.insert(literal)
                    }
                }
            }
        }
        #expect(unscopedCalls >= 10, "the scan must see the unscoped calls, or it proves nothing")
        #expect(problems.isEmpty, "unscoped calls on profile operations without a reason: \(problems)")
        #expect(exempted == Set(documentedExemptions.keys), "each documented exemption needs a real unscoped call")
    }
}
