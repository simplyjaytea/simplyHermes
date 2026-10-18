import Foundation
import HermesKit
import Testing

/// Request shape and decoding for the provider, OAuth, env and credential-pool calls.
@Suite struct ProviderEndpointTests {
    /// The request body as JSON, so keys and types can be compared exactly.
    private func json(_ request: HTTPRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.body))
    }

    @Test func providerKeyValidationIsNotScopedAndDecodes() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":false,"reachable":true,"message":"Key refused","extra":1}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        let refused = try await client.validateProviderKey(ApiKeyWrite(key: "OPENROUTER_API_KEY", value: "sk-1"))
        #expect(refused == ProviderCredentialCheck(ok: false, reachable: true, message: "Key refused"))
        let accepted = try await client.validateProviderKey(ApiKeyWrite(key: "K", value: "v"))
        #expect(accepted.ok && accepted.reachable == nil && accepted.message == nil)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/providers/validate")
        #expect(request.url.query == nil, "the contract has no profile parameter here")
        let expected: JSONValue = .object([
            "key": .string("OPENROUTER_API_KEY"), "value": .string("sk-1"), "provider_setup": .bool(false),
        ])
        #expect(try json(request) == expected)
    }

    @Test func customEndpointSaveSendsSnakeCaseAndOmitsNilFields() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"id":"lab"}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        let detail = ProviderCustomEndpointModelDetail(id: "qwen", canonicalModel: "qwen-7b", reasoningEffort: "high")
        let full = ProviderCustomEndpointDraft(
            name: "Lab", baseUrl: "http://192.168.1.20:8000/v1", model: "qwen", apiKey: "k-1",
            apiMode: .chatCompletions, contextLength: 32000, models: ["qwen"], modelDetails: [detail])
        let saved = try await client.saveCustomEndpoint(full)
        #expect(saved == .object(["ok": .bool(true), "id": .string("lab")]))
        let first = try #require(http.requests.first)
        #expect(first.method == "POST" && first.url.path == "/api/providers/custom-endpoints")
        #expect(first.url.query == "profile=ops")
        let expected: JSONValue = .object([
            "id": .string(""), "name": .string("Lab"), "base_url": .string("http://192.168.1.20:8000/v1"),
            "model": .string("qwen"), "api_key": .string("k-1"), "api_mode": .string("chat_completions"),
            "context_length": .int(32000), "discover_models": .bool(true), "make_default": .bool(false),
            "models": .array([.string("qwen")]),
            "model_details": .array([
                .object([
                    "id": .string("qwen"), "canonical_model": .string("qwen-7b"), "reasoning_effort": .string("high"),
                ])
            ]),
        ])
        #expect(try json(first) == expected)

        let minimal = ProviderCustomEndpointDraft(name: "Mini", baseUrl: "http://x/v1", model: "m", makeDefault: true)
        _ = try await client.validateCustomEndpoint(minimal)
        let second = try #require(http.requests.last)
        #expect(second.url.path == "/api/providers/custom-endpoints/validate")
        #expect(second.url.query == nil, "validate is not profile-scoped")
        let sent = try json(second)
        #expect(sent["api_key"] == nil && sent["api_mode"] == nil && sent["context_length"] == nil)
        #expect(sent["models"] == nil && sent["model_details"] == nil)
        #expect(sent["make_default"] == .bool(true) && sent["discover_models"] == .bool(true))
    }

    @Test func customEndpointListDeleteAndActivateEncodeTheID() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"[{"id":"lab","base_url":"http://x/v1"}]"#)
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        let list = try await client.customEndpoints()
        #expect(list == .array([.object(["id": .string("lab"), "base_url": .string("http://x/v1")])]))
        try await client.deleteCustomEndpoint(id: "a/b c")
        try await client.activateCustomEndpoint(id: "a/b c")
        _ = try await client.oauthProviders()
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "DELETE", "POST", "GET"])
        #expect(requests[1].url.path == "/api/providers/custom-endpoints/a%2Fb%20c")
        #expect(requests[2].url.path == "/api/providers/custom-endpoints/a%2Fb%20c/activate")
        #expect(requests[1].body == nil && requests[2].body == nil)
    }

    @Test func oauthCallsUseTheProviderAndSessionPaths() async throws {
        let http = FakeHTTP()
        for _ in 0..<7 { http.enqueue(200, #"{"status":"pending","session_id":"s/1"}"#) }
        let client = makeClient(http, profile: "ops")
        _ = try await client.oauthProviders()
        _ = try await client.startOAuthLogin(provider: "nous")
        _ = try await client.pollOAuthLogin(provider: "nous", session: "s/1")
        _ = try await client.submitOAuthCode(provider: "nous", ProviderOAuthSubmit(sessionId: "s1", code: "123456"))
        try await client.cancelOAuthLogin(session: "s1")
        try await client.disconnectOAuthProvider("nous")
        _ = try await client.oauthProviders()
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "POST", "GET", "POST", "DELETE", "DELETE", "GET"])
        #expect(requests[0].url.query == "profile=ops")
        #expect(requests[1].url.path == "/api/providers/oauth/nous/start")
        #expect(requests[2].url.path == "/api/providers/oauth/nous/poll/s%2F1")
        #expect(requests[3].url.path == "/api/providers/oauth/nous/submit")
        #expect(try json(requests[3]) == .object(["session_id": .string("s1"), "code": .string("123456")]))
        #expect(requests[4].url.path == "/api/providers/oauth/sessions/s1")
        #expect(requests[5].url.path == "/api/providers/oauth/nous")
        #expect(requests[6].url.query == "profile=ops")
    }

    @Test func apiKeyWritesSendTheNameAndValueOnly() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        try await client.setApiKey(ApiKeyWrite(key: "OPENROUTER_API_KEY", value: "sk-live"))
        try await client.deleteApiKey(named: "OPENROUTER_API_KEY")
        let put = try #require(http.requests.first)
        #expect(put.method == "PUT" && put.url.path == "/api/env" && put.url.query == "profile=ops")
        let written: JSONValue = .object([
            "key": .string("OPENROUTER_API_KEY"), "value": .string("sk-live"), "provider_setup": .bool(false),
        ])
        #expect(try json(put) == written)
        let delete = try #require(http.requests.last)
        #expect(delete.method == "DELETE" && delete.url.path == "/api/env")
        #expect(try json(delete) == .object(["key": .string("OPENROUTER_API_KEY")]))
    }

    @Test func revealRunsOnlyWhenAskedFor() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"[{"key":"A"}]"#)
        http.enqueue(200, #"[{"provider":"openrouter"}]"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        try await client.setApiKey(ApiKeyWrite(key: "A", value: "x"))
        _ = try await client.envVars()
        _ = try await client.credentialPool()
        try await client.deleteApiKey(named: "A")
        #expect(http.requests.allSatisfy { $0.url.path != "/api/env/reveal" }, "no reveal without an explicit call")

        http.enqueue(200, #"{"key":"OPENROUTER_API_KEY","value":"sk-live"}"#)
        let answer = try await client.revealApiKey(named: "OPENROUTER_API_KEY")
        #expect(answer == .object(["key": .string("OPENROUTER_API_KEY"), "value": .string("sk-live")]))
        let reveals = http.requests.filter { $0.url.path == "/api/env/reveal" }
        #expect(reveals.count == 1 && reveals.first?.method == "POST")
        #expect(try json(try #require(reveals.first)) == .object(["key": .string("OPENROUTER_API_KEY")]))
    }

    @Test func credentialPoolAddAndRemove() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"[{"provider":"openrouter"}]"#)
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        _ = try await client.credentialPool()
        _ = try await client.addCredential(CredentialPoolDraft(provider: "openrouter", apiKey: "sk-2", label: "work"))
        _ = try await client.addCredential(CredentialPoolDraft(provider: "nous", apiKey: "sk-3"))
        try await client.removeCredential(provider: "open router", index: 2)
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "POST", "POST", "DELETE"])
        let labelled: JSONValue = .object([
            "provider": .string("openrouter"), "api_key": .string("sk-2"), "label": .string("work"),
        ])
        #expect(try json(requests[1]) == labelled)
        #expect(try json(requests[2]) == .object(["provider": .string("nous"), "api_key": .string("sk-3")]))
        #expect(requests[3].url.path == "/api/credentials/pool/open%20router/2")
    }
}
