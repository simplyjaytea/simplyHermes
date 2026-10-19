import Foundation
import HermesKit
import Testing

/// The four learning calls: the request each builds (path, query, profile in the query and the body) and how
/// refusals reach the screen (WP-52, WP-41 profile rule).
@Suite struct JourneyEndpointTests {
    private func query(_ request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func body(_ request: HTTPRequest) throws -> [String: Any] {
        let data = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func graphCarriesTheActiveProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("learning_graph"))
        let graph = try await makeClient(http, profile: "ops").learningGraph()
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/learning/graph")
        #expect(query(request) == ["profile": "ops"])
        #expect(graph.nodes.count == 9 && graph.stats["nodes"] == JSONValue.int(9))
    }

    @Test func graphWithoutAProfileAddsNoQuery() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("learning_graph"))
        _ = try await makeClient(http).learningGraph()
        #expect(http.requests.first?.url.query == nil)
    }

    @Test func nodeContentAsksByIDAndProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("learning_node_memory"))
        let detail = try await makeClient(http, profile: "ops").learningNode(id: "memory:memory:0:3f9a1c2b")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/learning/node")
        #expect(query(request) == ["id": "memory:memory:0:3f9a1c2b", "profile": "ops"])
        #expect(detail.content.hasPrefix("JT likes short answers."))
    }

    @Test func nodeIDsWithSpecialCharactersStayOneValue() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("learning_node_skill"))
        _ = try await makeClient(http).learningNode(id: "a&b=c d+e#f")
        #expect(query(try #require(http.requests.first))["id"] == "a&b=c d+e#f")
    }

    @Test func editSendsTheTextWithTheProfileInQueryAndBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"message":"saved"}"#)
        let result = try await makeClient(http, profile: "ops").updateLearningNode(
            id: "backup-cron-fix", content: "# New")
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/learning/node")
        #expect(query(request) == ["profile": "ops"])
        #expect(request.headers["Content-Type"] == "application/json")
        let sent = try body(request)
        #expect(sent["id"] as? String == "backup-cron-fix" && sent["content"] as? String == "# New")
        #expect(sent["profile"] as? String == "ops")
        #expect(result == JourneyMutationResult(ok: true, message: "saved"))
    }

    @Test func editWithoutAProfileSendsNoProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        try await makeClient(http).updateLearningNode(id: "x", content: "y")
        let request = try #require(http.requests.first)
        #expect(request.url.query == nil)
        #expect(try body(request)["profile"] == nil)
    }

    @Test func deleteNamesTheNodeAndTheProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"message":"archived 'x' — restore with: hermes curator restore x"}"#)
        let result = try await makeClient(http, profile: "ops").deleteLearningNode(id: "x")
        let request = try #require(http.requests.first)
        #expect(request.method == "DELETE" && request.url.path == "/api/learning/node")
        #expect(query(request) == ["profile": "ops"])
        let sent = try body(request)
        #expect(sent["id"] as? String == "x" && sent["profile"] as? String == "ops")
        #expect(result.message?.hasPrefix("archived 'x'") == true)
    }

    @Test func profileChangesApplyToTheNextCall() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        try await client.deleteLearningNode(id: "x")
        await client.setProfile("research")
        try await client.deleteLearningNode(id: "x")
        let sent = try http.requests.map { try body($0)["profile"] as? String }
        #expect(sent == ["ops", "research"])
        #expect(http.requests.map { query($0)["profile"] } == ["ops", "research"])
    }

    @Test func refusalsKeepTheServersReason() async throws {
        let http = FakeHTTP()
        http.enqueue(409, #"{"detail":"x is pinned. Unpin it before deleting."}"#)
        http.enqueue(404, #"{"detail":"Unknown profile: nope"}"#)
        http.enqueue(400, #"{"detail":"SKILL.md needs a name."}"#)
        let client = makeClient(http, profile: "nope")
        await #expect(throws: RESTError.http(status: 409, detail: "x is pinned. Unpin it before deleting.")) {
            try await client.deleteLearningNode(id: "x")
        }
        await #expect(throws: RESTError.http(status: 404, detail: "Unknown profile: nope")) {
            try await client.learningGraph()
        }
        await #expect(throws: RESTError.http(status: 400, detail: "SKILL.md needs a name.")) {
            try await client.updateLearningNode(id: "x", content: "")
        }
    }

    @Test func okFalseOnASuccessStatusIsARefusal() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":false,"message":"nothing changed"}"#)
        http.enqueue(200, #"{"success":false}"#)
        let client = makeClient(http)
        await #expect(throws: RESTError.http(status: 200, detail: "nothing changed")) {
            try await client.updateLearningNode(id: "x", content: "y")
        }
        await #expect(throws: RESTError.http(status: 200, detail: "The server did not accept the change.")) {
            try await client.deleteLearningNode(id: "x")
        }
    }

    @Test func aWebPageInsteadOfDataIsReportedAsSuch() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "<html></html>", headers: ["Content-Type": "text/html"])
        await #expect(throws: RESTError.unexpectedContent(contentType: "text/html")) {
            try await makeClient(http).learningGraph()
        }
    }

    @Test func aBodyThatIsNotAGraphIsADecodingError() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "[1,2,3]")
        await #expect(throws: RESTError.self) { try await makeClient(http).learningGraph() }
    }
}
