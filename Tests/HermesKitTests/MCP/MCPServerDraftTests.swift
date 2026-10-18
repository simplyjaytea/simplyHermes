import Foundation
import HermesKit
import Testing

/// The add-server form builds the same body the server expects, and names the first field that is missing.
@Suite struct MCPServerDraftTests {
    @Test func commandServerKeepsArgumentsAndNamedVariablesOnly() throws {
        var draft = MCPServerDraft()
        draft.name = "  fs  "
        draft.command = "uvx"
        draft.argumentsText = "mcp-fs\n\n  /data  \n"
        draft.env = [
            MCPEnvPair(key: "API_KEY_2", value: "s3cret"), MCPEnvPair(), MCPEnvPair(key: " GITHUB_TOKEN ", value: "t"),
        ]
        let body = try draft.request()
        #expect(body.name == "fs" && body.command == "uvx" && body.args == ["mcp-fs", "/data"])
        #expect(body.env == ["API_KEY_2": "s3cret", "GITHUB_TOKEN": "t"])
        #expect(body.url == nil && body.auth == nil && body.bearerToken == nil)
    }

    @Test func urlServerWithOAuthDropsCommandFields() throws {
        var draft = MCPServerDraft()
        draft.name = "docs"
        draft.transport = .url
        draft.url = "https://docs.example/mcp"
        draft.auth = .oauth
        draft.command = "left over"
        draft.env = [MCPEnvPair(key: "X", value: "y")]
        let body = try draft.request()
        #expect(body.url == "https://docs.example/mcp" && body.auth == "oauth")
        #expect(body.command == nil && body.args.isEmpty && body.env.isEmpty && body.bearerToken == nil)
    }

    @Test func urlServerWithBearerTokenSendsHeaderAuth() throws {
        var draft = MCPServerDraft()
        draft.name = "api"
        draft.transport = .url
        draft.url = " https://api.example/mcp "
        draft.auth = .bearerToken
        draft.bearerToken = " tok "
        let body = try draft.request()
        #expect(body.url == "https://api.example/mcp" && body.auth == "header" && body.bearerToken == "tok")
    }

    @Test func urlServerWithoutAuthSendsNoAuthField() throws {
        var draft = MCPServerDraft()
        draft.name = "open"
        draft.transport = .url
        draft.url = "http://192.168.1.20:8000/mcp"
        let body = try draft.request()
        #expect(body.url == "http://192.168.1.20:8000/mcp" && body.auth == nil && body.bearerToken == nil)
    }

    @Test func problemsNameTheFirstMissingField() {
        var draft = MCPServerDraft()
        #expect(throws: MCPDraftProblem.nameRequired) { _ = try draft.request() }
        draft.name = "fs"
        #expect(throws: MCPDraftProblem.commandRequired) { _ = try draft.request() }
        draft.transport = .url
        #expect(throws: MCPDraftProblem.urlRequired) { _ = try draft.request() }
        draft.url = "https://api.example/mcp"
        draft.auth = .bearerToken
        #expect(throws: MCPDraftProblem.tokenRequired) { _ = try draft.request() }
    }

    @Test func variableProblemsAreReported() {
        var draft = MCPServerDraft()
        draft.name = "fs"
        draft.command = "uvx"
        draft.env = [MCPEnvPair(key: "", value: "orphan")]
        #expect(throws: MCPDraftProblem.variableNameRequired) { _ = try draft.request() }
        draft.env = [MCPEnvPair(key: "A", value: "1"), MCPEnvPair(key: "A", value: "2")]
        #expect(throws: MCPDraftProblem.duplicateVariable("A")) { _ = try draft.request() }
    }

    @Test func everyProblemHasASentence() {
        let problems: [MCPDraftProblem] = [
            .nameRequired, .commandRequired, .urlRequired, .tokenRequired, .variableNameRequired,
            .duplicateVariable("A"),
        ]
        #expect(problems.allSatisfy { !$0.message.isEmpty })
        #expect(MCPDraftProblem.duplicateVariable("GITHUB_TOKEN").message.contains("GITHUB_TOKEN"))
    }
}
