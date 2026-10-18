import Foundation
import HermesKit
import Testing

/// Request shape and decoding for the model-default calls: options, assignments, auxiliary tasks, recommendations and MoA.
@Suite struct ModelDefaultsEndpointTests {
    private func json(_ request: HTTPRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try #require(request.body))
    }

    @Test func providerCatalogReadsTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("model_options"))
        http.enqueue(200, try restFixture("model_options"))
        let client = makeClient(http, profile: "ops")
        let catalog = try await client.providerCatalog(refresh: true, includeUnconfigured: true)
        let provider = try #require(catalog.providers.first)
        #expect(provider.slug == "custom" && provider.isCurrent == true && provider.authenticated == true)
        #expect(provider.models == ["fake-model"] && catalog.model == "fake-model")
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
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        try await client.assignModel(
            ModelDefaultsAssignment(scope: .main, provider: "openrouter", model: "qwen/qwen3"))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/model/set" && request.url.query == nil)
        let expected: JSONValue = .object([
            "scope": .string("main"), "provider": .string("openrouter"), "model": .string("qwen/qwen3"),
            "task": .string(""), "confirm_expensive_model": .bool(false),
        ])
        #expect(try json(request) == expected)

        try await client.assignModel(
            ModelDefaultsAssignment(
                scope: .auxiliary, provider: "auto", model: "", task: "vision", reasoningEffort: "high"))
        let auxiliary = try json(try #require(http.requests.last))
        #expect(auxiliary["reasoning_effort"] == .string("high") && auxiliary["task"] == .string("vision"))
        #expect(auxiliary["scope"] == .string("auxiliary") && auxiliary["base_url"] == nil)
        #expect(auxiliary["api_key"] == nil)
    }

    @Test func auxiliaryTasksDecodeAndKeepTheirOrder() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"tasks":[
              {"task":"vision","provider":"openrouter","model":"m-vision","base_url":"",
               "label":null,"hint":null,"plugin":null,"inherit_from":"main",
               "effective":{"provider":"x"}},
              {"task":"tts","provider":"auto","model":"","base_url":"",
               "label":"Voice","hint":"Speech","plugin":"voice"}
            ],"main":{"provider":"openrouter","model":"m-main"}}
            """#
        )
        let client = makeClient(http)
        let answer = try await client.auxiliaryModels()
        #expect(answer.tasks.map(\.task) == ["vision", "tts"] && answer.tasks.map(\.id) == ["vision", "tts"])
        let vision = try #require(answer.tasks.first)
        #expect(vision.provider == "openrouter" && vision.model == "m-vision" && vision.inheritFrom == "main")
        #expect(vision.label == nil && vision.plugin == nil)
        let tts = answer.tasks[1]
        #expect(tts.label == "Voice" && tts.hint == "Speech" && tts.plugin == "voice" && tts.inheritFrom == nil)
        #expect(answer.main == ModelDefaultsSlot(provider: "openrouter", model: "m-main"))
        #expect(http.requests.first?.url.path == "/api/model/auxiliary")
    }

    @Test func recommendedModelSendsTheProvider() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"provider":"nous","model":"","free_tier":null}"#)
        http.enqueue(200, #"{"provider":"nous","model":"nous-large","free_tier":true}"#)
        let client = makeClient(http)
        let empty = try await client.recommendedModel(provider: "nous")
        #expect(empty == ModelDefaultsRecommendation(provider: "nous", model: "", freeTier: nil))
        let free = try await client.recommendedModel(provider: "nous team")
        #expect(free.model == "nous-large" && free.freeTier == true)
        #expect(http.requests.map(\.url.query) == ["provider=nous", "provider=nous%20team"])
    }

    @Test func moaRoundTripsTheWholeDocument() async throws {
        let http = FakeHTTP()
        let stored = #"{"enabled":true,"default_preset":"My_Preset","presets":{"My_Preset":{"fanout":"all"}}}"#
        http.enqueue(200, stored)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        let document = try await client.moaModels()
        #expect(document["default_preset"] == .string("My_Preset"))
        #expect(document["presets"]?["My_Preset"]?["fanout"] == .string("all"))
        var changed = document
        if case .object(var fields) = changed {
            fields["enabled"] = .bool(false)
            changed = .object(fields)
        }
        try await client.setMoaModels(changed)
        let put = try #require(http.requests.last)
        #expect(put.method == "PUT" && put.url.path == "/api/model/moa")
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(put.body))
        #expect(sent["enabled"] == .bool(false))
        #expect(sent["default_preset"] == .string("My_Preset"))
        #expect(sent["presets"]?["My_Preset"]?["fanout"] == .string("all"))
    }
}
