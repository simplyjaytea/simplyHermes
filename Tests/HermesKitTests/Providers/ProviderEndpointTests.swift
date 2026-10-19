import Foundation
import HermesKit
import Testing

/// Request shape and decoding for the provider, OAuth, env and credential-pool calls. Recorded requests and answers
/// come from Fixtures/rest, so the bodies are compared with what the testbed really sent.
@Suite struct ProviderEndpointTests {
    /// The request body as JSON, so keys and types can be compared exactly.
    private func json(_ request: HTTPRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.body))
    }

    @Test func providerKeyCheckIsNotScopedAndSendsNameAndValue() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        try await client.validateProviderKey(ApiKeyWrite(key: "PROVIDER_KEY", value: "secret-1"))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/providers/validate")
        #expect(request.url.query == nil, "the contract has no profile parameter here")
        #expect(try json(request) == .object(["key": .string("PROVIDER_KEY"), "value": .string("secret-1")]))
    }

    @Test func customEndpointSaveAndValidateSendTheRecordedBodies() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("POST_api_providers_custom-endpoints"))
        http.enqueue(200, try recordedFixtureAnswer("POST_api_providers_custom-endpoints_validate"))
        let client = makeClient(http, profile: "ops")
        let draft = try recordedFixtureBody("POST_api_providers_custom-endpoints", as: ProviderCustomEndpointDraft.self)
        try await client.saveCustomEndpoint(draft)
        _ = try await client.validateCustomEndpoint(draft)
        let requests = http.requests
        #expect(
            requests.map(\.url.path) == ["/api/providers/custom-endpoints", "/api/providers/custom-endpoints/validate"])
        #expect(requests[0].url.query == "profile=ops")
        #expect(requests[1].url.query == nil, "validate is not profile-scoped")
        let recordedSave = try recordedFixtureRequest("POST_api_providers_custom-endpoints")
        let recordedValidate = try recordedFixtureRequest("POST_api_providers_custom-endpoints_validate")
        #expect(try json(requests[0]) == recordedSave["body"])
        #expect(try json(requests[1]) == recordedValidate["body"])
    }

    @Test func customEndpointSendsOptionalFieldsWhenSet() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        let full = ProviderCustomEndpointDraft(
            name: "Lab", baseUrl: "http://192.168.1.20:8000/v1", model: "example-model", apiKey: "k-1",
            apiMode: ProviderAPIModes.chatCompletions, contextLength: 32000, makeDefault: true)
        try await client.saveCustomEndpoint(full)
        let sent = try json(try #require(http.requests.first))
        #expect(sent["api_key"] == .string("k-1") && sent["api_mode"] == .string("chat_completions"))
        #expect(sent["context_length"] == .int(32000) && sent["make_default"] == .bool(true))
        #expect(sent["id"] == nil, "the server assigns the id on create")
    }

    @Test func customEndpointListDecodesTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_providers_custom-endpoints.seeded"))
        let client = makeClient(http)
        let list = try await client.customEndpoints()
        #expect(!list.endpoints.isEmpty)
        #expect(list.endpoints.allSatisfy { !$0.id.isEmpty && !$0.baseUrl.isEmpty })
        #expect(list.endpoints.allSatisfy { $0.isCurrent != nil && $0.hasApiKey != nil })
        #expect(http.requests.first?.url.path == "/api/providers/custom-endpoints")
    }

    @Test func customEndpointDeleteAndActivateEncodeTheID() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("DELETE_api_providers_custom-endpoints_endpoint_id"))
        http.enqueue(200, #"{}"#)
        let client = makeClient(http, profile: "ops")
        try await client.deleteCustomEndpoint(id: "recorder-endpoint")
        try await client.activateCustomEndpoint(id: "a/b c")
        let requests = http.requests
        let recorded = try recordedFixtureRequest("DELETE_api_providers_custom-endpoints_endpoint_id")
        #expect(recorded["method"] == .string("DELETE") && requests[0].method == "DELETE")
        #expect(requests[0].url.path == "/api/providers/custom-endpoints/recorder-endpoint")
        #expect(requests[1].method == "POST")
        #expect(requests[1].url.path == "/api/providers/custom-endpoints/a%2Fb%20c/activate")
        #expect(requests[0].body == nil && requests[1].body == nil)
    }

    @Test func oauthCallsUseTheProviderAndSessionPaths() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_providers_oauth"))
        for _ in 0..<5 { http.enqueue(200, #"{"status":"pending"}"#) }
        let client = makeClient(http, profile: "ops")
        _ = try await client.oauthProviders()
        try await client.startOAuthLogin(provider: "nous")
        _ = try await client.pollOAuthLogin(provider: "nous", session: "s/1")
        try await client.submitOAuthCode(provider: "nous", ProviderOAuthSubmit(sessionId: "s1", code: "123456"))
        try await client.cancelOAuthLogin(session: "s1")
        try await client.disconnectOAuthProvider("nous")
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "POST", "GET", "POST", "DELETE", "DELETE"])
        #expect(requests[0].url.query == "profile=ops")
        #expect(requests[1].url.path == "/api/providers/oauth/nous/start")
        #expect(requests[2].url.path == "/api/providers/oauth/nous/poll/s%2F1")
        #expect(requests[3].url.path == "/api/providers/oauth/nous/submit")
        #expect(try json(requests[3]) == .object(["session_id": .string("s1"), "code": .string("123456")]))
        #expect(requests[4].url.path == "/api/providers/oauth/sessions/s1")
        #expect(requests[5].url.path == "/api/providers/oauth/nous")
    }

    @Test func apiKeyWritesSendTheRecordedBodies() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("PUT_api_env"))
        http.enqueue(200, try recordedFixtureAnswer("DELETE_api_env"))
        let client = makeClient(http, profile: "ops")
        let write = try recordedFixtureBody("PUT_api_env", as: ApiKeyWrite.self)
        try await client.setApiKey(write)
        let remove = try recordedFixtureBody("DELETE_api_env", as: ApiKeyNameRequest.self)
        try await client.deleteApiKey(named: remove.key)
        let requests = http.requests
        #expect(requests.map(\.method) == ["PUT", "DELETE"] && requests[0].url.path == "/api/env")
        #expect(requests[0].url.query == "profile=ops")
        #expect(try json(requests[0]) == recordedFixtureRequest("PUT_api_env")["body"])
        #expect(try json(requests[1]) == recordedFixtureRequest("DELETE_api_env")["body"])
    }

    @Test func envListDecodesTypesAndKeepsValuesOut() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_env.seeded"))
        let client = makeClient(http)
        let env = try await client.envVars()
        #expect(!env.isEmpty)
        #expect(env.values.allSatisfy { $0.isSet != nil && $0.isPassword != nil })
        #expect(env.values.contains { $0.isSet == true }, "the seeded run sets one variable")
        #expect(http.requests.first?.url.path == "/api/env")
    }

    @Test func revealRunsOnlyWhenAskedFor() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("PUT_api_env"))
        http.enqueue(200, try recordedFixtureAnswer("GET_api_env.seeded"))
        http.enqueue(200, try recordedFixtureAnswer("GET_api_credentials_pool.seeded"))
        http.enqueue(200, try recordedFixtureAnswer("DELETE_api_env"))
        http.enqueue(200, #"{"value":"stored"}"#)
        let client = makeClient(http)
        try await client.setApiKey(ApiKeyWrite(key: "A", value: "x"))
        _ = try await client.envVars()
        _ = try await client.credentialPool()
        try await client.deleteApiKey(named: "A")
        #expect(http.requests.allSatisfy { $0.url.path != "/api/env/reveal" }, "no reveal without an explicit call")

        _ = try await client.revealApiKey(named: "A")
        let reveals = http.requests.filter { $0.url.path == "/api/env/reveal" }
        #expect(reveals.count == 1 && reveals.first?.method == "POST")
        #expect(try json(try #require(reveals.first)) == .object(["key": .string("A")]))
    }

    @Test func credentialPoolDecodesTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_credentials_pool"))
        http.enqueue(200, try recordedFixtureAnswer("GET_api_credentials_pool.seeded"))
        let client = makeClient(http)
        let empty = try await client.credentialPool()
        #expect(empty.providers.isEmpty)
        let seeded = try await client.credentialPool()
        let group = try #require(seeded.providers.first)
        let entry = try #require(group.entries.first)
        #expect(!group.provider.isEmpty && !entry.id.isEmpty)
        #expect(entry.index >= 1, "the pool numbers its entries from 1")
        #expect(entry.label != nil && entry.authType != nil && entry.source != nil && entry.requestCount != nil)
    }

    @Test func credentialPoolAddAndRemoveUseTheRecordedBodyAndIndex() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("POST_api_credentials_pool"))
        http.enqueue(200, #"{}"#)
        let client = makeClient(http)
        let draft = try recordedFixtureBody("POST_api_credentials_pool", as: CredentialPoolDraft.self)
        try await client.addCredential(draft)
        try await client.removeCredential(provider: "open router", index: 2)
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "DELETE"])
        #expect(try json(requests[0]) == recordedFixtureRequest("POST_api_credentials_pool")["body"])
        #expect(requests[1].url.path == "/api/credentials/pool/open%20router/2")
    }

    @Test func credentialRemovalSurfacesTheRecordedNotFound() async throws {
        let http = FakeHTTP()
        http.enqueue(404, try recordedFixtureAnswer("DELETE_api_credentials_pool_recorder_0"))
        let client = makeClient(http)
        do {
            try await client.removeCredential(provider: "recorder", index: 0)
            Issue.record("a missing index must throw")
        } catch RESTError.http(let status, let detail) {
            #expect(status == 404 && detail != nil)
        }
    }

    @Test func credentialEntryIsLookedUpInTheListGiven() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_credentials_pool.seeded"))
        let client = makeClient(http)
        let listing = try await client.credentialPool()
        let group = try #require(listing.providers.first)
        let entry = try #require(group.entries.first)
        #expect(listing.entry(id: entry.id, provider: group.provider) == entry)
        #expect(listing.entry(id: entry.id, provider: "other-provider") == nil)
        #expect(listing.entry(id: "not-pooled", provider: group.provider) == nil)
        // The index comes from the listing given, so a later read that moved the entry is the one a removal uses.
        var moved = listing
        moved.providers[0].entries[0].index = entry.index + 1
        let target = try #require(moved.entry(id: entry.id, provider: group.provider))
        #expect(target.index == entry.index + 1)
    }
}
