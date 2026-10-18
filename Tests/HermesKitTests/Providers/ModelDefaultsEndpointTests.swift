import Foundation
import HermesKit
import Testing

/// Request shape and decoding for the model-default calls: options, assignments, auxiliary tasks, recommendations and MoA.
/// Recorded answers come from Fixtures/rest; the tests check types, not sample values.
@Suite struct ModelDefaultsEndpointTests {
    private func json(_ request: HTTPRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.body))
    }

    @Test func providerCatalogDecodesTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_model_options"))
        http.enqueue(200, try recordedFixtureAnswer("GET_api_model_options"))
        let client = makeClient(http, profile: "ops")
        let catalog = try await client.providerCatalog(refresh: true, includeUnconfigured: true)
        #expect(!catalog.providers.isEmpty)
        #expect(catalog.providers.allSatisfy { !$0.slug.isEmpty && $0.authenticated != nil && $0.totalModels != nil })
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/model/options")
        #expect(request.url.query == "refresh=true&include_unconfigured=true&profile=ops")
        _ = try await client.providerCatalog()
        #expect(http.requests.last?.url.query == "profile=ops")
    }

    @Test func providerCatalogKeepsUnconfiguredProviders() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"providers":[{"slug":"nous","name":"Nous","authenticated":false,
            "is_current":false,"models":[],"total_models":0,"source":"x"}]}
            """#
        )
        let client = makeClient(http)
        let catalog = try await client.providerCatalog(includeUnconfigured: true)
        #expect(catalog.providers.first?.authenticated == false && catalog.model == nil)
        #expect(http.requests.first?.url.query == "include_unconfigured=true")
    }

    @Test func mainAssignmentOmitsEmptyOptionals() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{}"#)
        http.enqueue(200, #"{}"#)
        let client = makeClient(http)
        try await client.assignModel(
            ModelDefaultsAssignment(scope: ModelDefaultsScopes.main, provider: "openrouter", model: "example/model"))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/model/set" && request.url.query == nil)
        let expected: JSONValue = .object([
            "scope": .string("main"), "provider": .string("openrouter"), "model": .string("example/model"),
            "task": .string(""), "confirm_expensive_model": .bool(false),
        ])
        #expect(try json(request) == expected)

        try await client.assignModel(
            ModelDefaultsAssignment(
                scope: ModelDefaultsScopes.auxiliary, provider: "auto", model: "", task: "vision",
                reasoningEffort: "high"))
        let auxiliary = try json(try #require(http.requests.last))
        #expect(auxiliary["reasoning_effort"] == .string("high") && auxiliary["task"] == .string("vision"))
        #expect(auxiliary["scope"] == .string("auxiliary") && auxiliary["base_url"] == nil)
    }

    @Test func auxiliaryTasksDecodeTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_model_auxiliary"))
        let client = makeClient(http)
        let answer = try await client.auxiliaryModels()
        #expect(!answer.tasks.isEmpty)
        let names = answer.tasks.map(\.id)
        #expect(Set(names).count == names.count, "each task appears once")
        #expect(answer.tasks.allSatisfy { $0.provider != nil && $0.model != nil && $0.baseUrl != nil })
        #expect(answer.main != nil)
        #expect(http.requests.first?.url.path == "/api/model/auxiliary")
    }

    @Test func auxiliaryTaskDecodesStoredEffortAndIgnoresUnrecordedFields() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"tasks":[
              {"task":"vision","provider":"openrouter","model":"m-vision","base_url":"",
               "reasoning_effort":"high","label":"Vision","plugin":"x","effective":{"provider":"y"}},
              {"task":"tts","provider":"auto","model":"","base_url":"","reasoning_effort":null}
            ],"main":{"provider":"openrouter","model":"m-main"}}
            """#
        )
        let client = makeClient(http)
        let answer = try await client.auxiliaryModels()
        #expect(answer.tasks.map(\.task) == ["vision", "tts"])
        #expect(answer.tasks[0].reasoningEffort == "high" && answer.tasks[1].reasoningEffort == nil)
        #expect(answer.main == ModelDefaultsSlot(provider: "openrouter", model: "m-main"))
    }

    @Test func recommendedModelDecodesTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedFixtureAnswer("GET_api_model_recommended-default"))
        http.enqueue(200, #"{"provider":"nous","model":"nous-large"}"#)
        let client = makeClient(http)
        let recorded = try await client.recommendedModel(provider: "nous")
        #expect(recorded.provider != nil && recorded.model != nil)
        let second = try await client.recommendedModel(provider: "nous team")
        #expect(second.model == "nous-large")
        #expect(http.requests.map(\.url.query) == ["provider=nous", "provider=nous%20team"])
    }

    @Test func moaRoundTripsTheRecordedDocument() async throws {
        let http = FakeHTTP()
        let stored = try recordedFixtureAnswer("GET_api_model_moa")
        http.enqueue(200, stored)
        http.enqueue(200, #"{}"#)
        let client = makeClient(http)
        let document = try await client.moaModels()
        #expect(document == (try JSONDecoder().decode(JSONValue.self, from: Data(stored.utf8))))
        var changed = document
        if case .object(var fields) = changed {
            fields["enabled"] = .bool(false)
            changed = .object(fields)
        }
        try await client.setMoaModels(changed)
        let put = try #require(http.requests.last)
        #expect(put.method == "PUT" && put.url.path == "/api/model/moa")
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(put.body))
        #expect(sent == changed, "the whole document goes back, not a partial one")
    }
}
