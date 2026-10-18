import Foundation
import HermesKit
import Testing

/// Each test scripts the answers the server gives and checks the request the client built. The reads are decoded from
/// recorded answers. The writes are checked by their HTTP status.
@Suite struct MCPEndpointTests {
    private func jsonObject(_ request: HTTPRequest) throws -> [String: Any] {
        try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    }

    @Test func addSendsSnakeCaseBodyAndKeepsVariableNames() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"name":"fs","transport":"stdio","enabled":true,"source":"config"}"#)
        let server = MCPServerCreate(
            name: "fs", command: "uvx", args: ["mcp-fs"], env: ["GITHUB_TOKEN": "t0k3n", "api_key_2": "x"])
        try await makeClient(http).addMCPServer(server)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/mcp/servers" && request.url.query == nil)
        let body = try jsonObject(request)
        #expect(Set(body.keys) == ["name", "command", "args", "env"])
        #expect(body["env"] as? [String: String] == ["GITHUB_TOKEN": "t0k3n", "api_key_2": "x"])
        #expect(body["args"] as? [String] == ["mcp-fs"])
    }

    @Test func addHTTPServerWithHeaderAuthSendsTheTokenAsBearerToken() async throws {
        let http = FakeHTTP()
        http.enqueue(200)
        let server = MCPServerCreate(
            name: "api", url: "https://api.example/mcp", auth: "header", bearerToken: "tok")
        try await makeClient(http).addMCPServer(server)
        let body = try jsonObject(try #require(http.requests.first))
        #expect(body["url"] as? String == "https://api.example/mcp" && body["auth"] as? String == "header")
        #expect(body["bearer_token"] as? String == "tok" && body["bearerToken"] == nil)
        #expect(body["command"] == nil && body["auth"] != nil)
    }

    @Test func replaceSendsTheWholeMap() async throws {
        let http = FakeHTTP()
        http.enqueue(200)
        let servers: [String: JSONValue] = [
            "docs": .object(["url": .string("https://docs.example/mcp"), "enabled": .bool(true)]),
            "fs": .object(["command": .string("uvx"), "enabled": .bool(false)]),
        ]
        try await makeClient(http).replaceMCPServers(servers)
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/mcp/servers" && request.url.query == nil)
        let map = try #require(try jsonObject(request)["servers"] as? [String: Any])
        #expect(Set(map.keys) == ["docs", "fs"])
        #expect((map["fs"] as? [String: Any])?["enabled"] as? Bool == false)
    }

    @Test func removeSendsTheExactNameInThePath() async throws {
        let http = FakeHTTP()
        http.enqueue(200)
        try await makeClient(http).removeMCPServer(named: "a b/c")
        let request = try #require(http.requests.first)
        #expect(request.method == "DELETE")
        #expect(request.url.path == "/api/mcp/servers/a%20b%2Fc")
    }

    @Test func enabledToggleSendsOnlyTheFlag() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"github","enabled":false}"#)
        try await makeClient(http).setMCPServerEnabled("github", enabled: false)
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/mcp/servers/github/enabled")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["enabled"] as? Bool == false)
    }

    @Test func testSendsOnePostAndChecksOnlyTheStatus() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":false,"error":"OAuth authentication required — no token found.","tools":[]}"#)
        try await makeClient(http).testMCPServer("docs")
        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/mcp/servers/docs/test")
    }

    @Test func refusedStatusThrowsWithTheServerDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(409, #"{"detail":"A server with this name exists."}"#)
        await #expect(throws: RESTError.http(status: 409, detail: "A server with this name exists.")) {
            try await makeClient(http).addMCPServer(MCPServerCreate(name: "fs", command: "uvx"))
        }
    }

    @Test func undecodedAnswerDoesNotFailACall() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "not json at all")
        try await makeClient(http).startMCPServerAuth("docs")
        #expect(http.requests.first?.method == "POST")
    }

    @Test func oauthStartPollAndCancelCheckOnlyTheStatus() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"flow_id":"f1","status":"authorization_required","authorization_url":"https://auth.example/authorize"}"#)
        http.enqueue(200, #"{"flow_id":"f1","status":"approved"}"#)
        http.enqueue(200, #"{"ok":true,"status":"expired"}"#)
        let client = makeClient(http)
        try await client.startMCPServerAuth("docs")
        try await client.checkMCPOAuthFlow(id: "f1")
        try await client.cancelMCPOAuthFlow(id: "f1")
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "GET", "DELETE"])
        #expect(
            requests.map { $0.url.path } == [
                "/api/mcp/servers/docs/auth", "/api/mcp/oauth/flows/f1", "/api/mcp/oauth/flows/f1",
            ])
    }

    @Test func installSendsOnlyDeclaredEnvAndChecksOnlyTheStatus() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"github","background":true,"action":"mcp-install-github-1a2b"}"#)
        try await makeClient(http).installMCPCatalogEntry(
            MCPCatalogInstall(name: "github", env: ["GITHUB_TOKEN": "t"]))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/mcp/catalog/install")
        let body = try jsonObject(request)
        #expect(body["name"] as? String == "github" && body["enable"] as? Bool == true)
        #expect(body["env"] as? [String: String] == ["GITHUB_TOKEN": "t"])
    }

    @Test func serversDecodeTheRecordedServer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedBody("GET_api_mcp_servers.seeded"))
        let servers = try await makeClient(http).mcpServers()
        let server = try #require(servers.first)
        #expect(!server.name.isEmpty)
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/mcp/servers" && request.url.query == nil)
    }

    @Test func serversAcceptTheEmptyRecordedList() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedBody("GET_api_mcp_servers"))
        let servers = try await makeClient(http).mcpServers()
        #expect(servers.isEmpty)
    }

    @Test func catalogDecodesEveryRecordedEntry() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedBody("GET_api_mcp_catalog"))
        let catalog = try await makeClient(http).mcpCatalog()
        #expect(!catalog.entries.isEmpty && catalog.entries.allSatisfy { !$0.name.isEmpty })
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/mcp/catalog")
    }

    @Test func profileScopeIsAddedToMCPCalls() async throws {
        let http = FakeHTTP()
        http.enqueue(200)
        try await makeClient(http, profile: "ops").removeMCPServer(named: "docs")
        #expect(http.requests.first?.url.query == "profile=ops")
    }
}
