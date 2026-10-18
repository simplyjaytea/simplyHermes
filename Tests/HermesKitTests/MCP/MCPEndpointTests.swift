import Foundation
import HermesKit
import Testing

/// Each test scripts the answers the server gives and checks the request the client built and the decoded values.
@Suite struct MCPEndpointTests {
    private static let serversJSON = #"""
        {"servers":[
          {"name":"github","transport":"stdio","url":null,"command":"npx","args":["-y","@x/github"],
           "env":{"GITHUB_TOKEN":"ghp_masked"},"auth":null,"enabled":true,"tools":null,"source":"config","plugin":null},
          {"name":"docs","transport":"http","url":"https://docs.example/mcp","command":null,"args":[],
           "env":{},"auth":"oauth","enabled":false,"tools":["search"],"source":"plugin","plugin":"docs-plugin",
           "future_field":{"ignored":true}}
        ]}
        """#

    private func jsonObject(_ request: HTTPRequest) throws -> [String: Any] {
        try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    }

    @Test func listDecodesServersAndNamesOnlyTheEnv() async throws {
        let http = FakeHTTP()
        http.enqueue(200, Self.serversJSON)
        let servers = try await makeClient(http).mcpServers()
        #expect(servers.map(\.name) == ["github", "docs"])
        let github = try #require(servers.first)
        #expect(github.enabled && github.isEditable && github.transport == "stdio")
        #expect(github.envNames == ["GITHUB_TOKEN"] && github.args == ["-y", "@x/github"])
        let docs = try #require(servers.last)
        #expect(!docs.enabled && !docs.isEditable && docs.auth == "oauth")
        #expect(docs.supportsOAuth && !github.supportsOAuth)
        #expect(docs.url == "https://docs.example/mcp" && docs.plugin == "docs-plugin")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/mcp/servers" && request.url.query == nil)
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

    @Test func testDecodesSuccessAndFailure() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"ok":true,"tools":[{"name":"search","description":"Search docs","schema_chars":120}],"prompts":0,"resources":2}"#
        )
        http.enqueue(200, #"{"ok":false,"error":"OAuth authentication required — no token found.","tools":[]}"#)
        let client = makeClient(http)
        let good = try await client.testMCPServer("docs")
        #expect(good.ok && good.resources == 2 && good.prompts == 0)
        #expect(good.tools?.first?.name == "search" && good.tools?.first?.schemaChars == 120)
        let bad = try await client.testMCPServer("docs")
        #expect(!bad.ok && bad.tools?.isEmpty == true)
        #expect(bad.error == "OAuth authentication required — no token found.")
        #expect(http.requests.allSatisfy { $0.method == "POST" && $0.url.path == "/api/mcp/servers/docs/test" })
    }

    @Test func oauthStartPollAndCancel() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"flow_id":"f1","server_name":"docs","status":"authorization_required","authorization_url":"https://auth.example/authorize?state=s","error":null,"tools":null}"#
        )
        http.enqueue(
            200,
            #"{"flow_id":"f1","server_name":"docs","status":"approved","authorization_url":null,"error":null,"tools":[{"name":"search","description":"Search"}]}"#
        )
        http.enqueue(200, #"{"ok":true,"status":"expired"}"#)
        let client = makeClient(http)
        let started = try await client.startMCPServerAuth("docs")
        #expect(started.flowId == "f1" && !started.isFinished && started.authorizationUrl != nil)
        let polled = try await client.mcpOAuthFlow(id: started.flowId)
        #expect(polled.isFinished && polled.isApproved && polled.tools?.first?.name == "search")
        try await client.cancelMCPOAuthFlow(id: "f1")
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "GET", "DELETE"])
        #expect(
            requests.map { $0.url.path } == [
                "/api/mcp/servers/docs/auth", "/api/mcp/oauth/flows/f1", "/api/mcp/oauth/flows/f1",
            ])
    }

    @Test func failedOAuthFlowFinishesWithItsError() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"flow_id":"f2","status":"error","error":"Cancelled by user"}"#)
        let flow = try await makeClient(http).mcpOAuthFlow(id: "f2")
        #expect(flow.isFinished && !flow.isApproved && flow.error == "Cancelled by user")
    }

    @Test func catalogDecodesEntriesAndDiagnostics() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"entries":[{"name":"github","description":"GitHub tools","connector_slug":null,"source":"nous",
              "transport":"stdio","auth_type":"env","required_env":[{"name":"GITHUB_TOKEN","prompt":"Token","required":true}],
              "command":"npx","args":["-y","@modelcontextprotocol/server-github"],"url":null,"install_url":null,
              "install_ref":null,"bootstrap":[],"default_enabled":null,"post_install":"","suggest":null,
              "needs_install":false,"installed":false,"enabled":false}],
             "diagnostics":[{"name":"broken","kind":"parse","message":"bad yaml"}]}
            """#)
        let catalog = try await makeClient(http).mcpCatalog()
        let entry = try #require(catalog.entries.first)
        #expect(entry.id == "github" && entry.installed == false && entry.transport == "stdio")
        #expect(entry.requiredEnv?.first?.name == "GITHUB_TOKEN" && entry.requiredEnv?.first?.required == true)
        #expect(catalog.diagnostics?.first?.message == "bad yaml")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/mcp/catalog")
    }

    @Test func installSendsOnlyDeclaredEnvAndReportsBackgroundWork() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"github","background":true,"action":"mcp-install-github-1a2b"}"#)
        let result = try await makeClient(http).installMCPCatalogEntry(
            MCPCatalogInstall(name: "github", env: ["GITHUB_TOKEN": "t"]))
        #expect(result.ok == true && result.background == true && result.action == "mcp-install-github-1a2b")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/mcp/catalog/install")
        let body = try jsonObject(request)
        #expect(body["name"] as? String == "github" && body["enable"] as? Bool == true)
        #expect(body["env"] as? [String: String] == ["GITHUB_TOKEN": "t"])
    }

    @Test func profileScopeIsAddedToMCPCalls() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"servers":[]}"#)
        _ = try await makeClient(http, profile: "ops").mcpServers()
        #expect(http.requests.first?.url.query == "profile=ops")
    }
}
