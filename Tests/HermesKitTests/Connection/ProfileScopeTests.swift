import Foundation
import HermesKit
import Testing

@Suite struct ProfileScopeTests {
    @Test func addsProfileToObjectParams() {
        let params = JSONValue.object(["session_id": .string("s1")])
        let scoped = ProfileScope.scoped(method: "session.history", params: params, profile: "ops")
        #expect(scoped == .object(["session_id": .string("s1"), "profile": .string("ops")]))
    }

    @Test func missingParamsBecomeAnObjectWithTheProfile() {
        #expect(
            ProfileScope.scoped(method: "profiles.list", params: nil, profile: "ops")
                == .object(["profile": .string("ops")]))
    }

    @Test func callerProfileWins() {
        let params = JSONValue.object(["profile": .string("other")])
        #expect(ProfileScope.scoped(method: "session.list", params: params, profile: "ops") == params)
    }

    @Test func noActiveProfileChangesNothing() {
        let params = JSONValue.object(["a": .int(1)])
        #expect(ProfileScope.scoped(method: "session.list", params: params, profile: nil) == params)
        #expect(ProfileScope.scoped(method: "session.list", params: nil, profile: nil) == nil)
    }

    @Test func methodsWithoutProfileAreLeftAlone() {
        #expect(ProfileScope.scoped(method: "gateway.ping", params: nil, profile: "ops") == nil)
        #expect(
            ProfileScope.scoped(method: "client.capabilities", params: .object([:]), profile: "ops") == .object([:]))
    }

    /// CI gate: the method list is exactly the contract's methods whose params schema has a `profile` property.
    @Test func methodListMatchesTheContract() throws {
        let contract = FixtureFiles.directory.deletingLastPathComponent()
            .appendingPathComponent("docs/protocol/gateway-contract.openrpc.json")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: contract)) as? [String: Any])
        let schemas = try #require((root["components"] as? [String: Any])?["schemas"] as? [String: Any])
        var expected: Set<String> = []
        for method in try #require(root["methods"] as? [[String: Any]]) {
            guard let name = method["name"] as? String,
                let first = (method["params"] as? [[String: Any]])?.first,
                let ref = (first["schema"] as? [String: Any])?["$ref"] as? String,
                let schema = schemas[String(ref.split(separator: "/").last ?? "")] as? [String: Any],
                (schema["properties"] as? [String: Any])?["profile"] != nil
            else { continue }
            expected.insert(name)
        }
        #expect(ProfileScope.rpcMethods == expected)
    }

    /// CI gate: only these REST calls may skip the active profile. Anything else with `scoped: false` fails here.
    @Test func onlyProfileFreeRESTCallsAreUnscoped() throws {
        let allowed: Set<String> = [
            "/api/health", "/api/host/identity", "/api/status", "/api/auth/me", "/api/profiles",
            "/api/profiles/active", "/api/auth/providers", "/auth/logout", "/api/auth/ws-ticket",
            "/auth/password-login",
            // Profile export and import name the profile in the path or body and take no `profile` query.
            "/api/profiles/", "/api/profiles/import",
        ]
        let sources = FixtureFiles.directory.deletingLastPathComponent().appendingPathComponent(
            "Sources/HermesKit/REST")
        var unscoped: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            // A call whose arguments (up to the next blank line or `}`) include `scoped: false`.
            let calls = text.components(separatedBy: "\n\n").flatMap { $0.components(separatedBy: "\n    }") }
            for call in calls where call.contains("scoped: false") {
                let paths = call.split(separator: "\"").filter { $0.hasPrefix("/") }.map(String.init)
                for path in paths where !allowed.contains(path) { unscoped.append("\(file): \(path)") }
            }
        }
        #expect(unscoped.isEmpty, "unscoped REST calls not on the allow list: \(unscoped)")
    }
}
