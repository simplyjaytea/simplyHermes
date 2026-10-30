import Foundation
import HermesKit
import Testing

/// Toolset calls: the switch, the provider picker, the model catalog, provider and model selection, provider keys and
/// post-setup. Each request is checked against the server's request model and the `profile` scope.
@Suite struct ToolsetsRESTTests {
    @Test func toggleSendsEnabledAndReadsTheStartedInstall() async throws {
        let (result, request) = try await skillsRun("toolset_toggle") {
            try await $0.setSkillToolsetEnabled("browser", enabled: true)
        }
        #expect(result.ok == true && result.platform == "cli" && result.enabled == true)
        #expect(result.postSetupStarted == "playwright")
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/browser")
        let body = try skillsJSONBody(request)
        #expect(body.count == 1 && body["enabled"] as? Bool == true)
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func configDecodesTheProviderPicker() async throws {
        let (config, request) = try await skillsRun("toolset_config") { try await $0.skillToolsetConfig("web") }
        #expect(config.name == "web" && config.hasCategory == true && config.activeProvider == "Firecrawl")
        let providers = try #require(config.providers)
        #expect(providers.map(\.name) == ["Firecrawl", "Nous Subscription"])
        #expect(providers.first?.isActive == true && providers.first?.status == "ready")
        #expect(providers.first?.envVars?.first?.key == "FIRECRAWL_API_KEY")
        #expect(providers.first?.envVars?.first?.isSet == true)
        #expect(providers.last?.requiresNousAuth == true && providers.last?.status == "needs_login")
        #expect(request.method == "GET" && request.url.path == "/api/tools/toolsets/web/config")
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func modelCatalogCarriesTheProviderAndDecodesDefault() async throws {
        let (catalog, request) = try await skillsRun("toolset_models") {
            try await $0.skillToolsetModels("image_gen", provider: "Example Images")
        }
        #expect(catalog.hasModels == true && catalog.current == "fast-model" && catalog.defaultModel == "fast-model")
        #expect(catalog.models?.map(\.id) == ["fast-model", "best-model"] && catalog.models?.last?.display == "Best")
        #expect(skillsQuery(request) == ["provider": "Example Images", "profile": "ops"])
        #expect(request.url.path == "/api/tools/toolsets/image_gen/models")
    }

    @Test func modelCatalogWithoutAProviderSendsNoProviderQuery() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("toolset_models"))
        let client = makeClient(http, profile: nil)
        _ = try await client.skillToolsetModels("image gen")
        let request = try #require(http.requests.first)
        #expect(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedPath
                == "/api/tools/toolsets/image%20gen/models")
        #expect(request.url.query == nil)
    }

    @Test func modelSelectOmitsAnUnsetProvider() async throws {
        let (selection, request) = try await skillsRun("toolset_model_selected") {
            try await $0.selectSkillToolsetModel("image_gen", model: "best-model")
        }
        #expect(selection.model == "best-model" && selection.plugin == "example-images")
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/image_gen/model")
        let body = try skillsJSONBody(request)
        #expect(body.count == 1 && body["model"] as? String == "best-model")
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func providerSelectSendsCapabilityAndReadsEntitlement() async throws {
        let (selection, request) = try await skillsRun("toolset_provider_selected") {
            try await $0.selectSkillToolsetProvider("web", provider: "Nous Subscription", capability: "search")
        }
        #expect(selection.needsNousAuth == true && selection.feature == "web" && selection.capability == "search")
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/web/provider")
        let body = try skillsJSONBody(request)
        #expect(body["provider"] as? String == "Nous Subscription" && body["capability"] as? String == "search")
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func envUpdateKeepsVariableNamesExactly() async throws {
        let (saved, request) = try await skillsRun("toolset_env_saved") {
            try await $0.saveSkillToolsetEnv("web", env: ["FIRECRAWL_API_KEY": "fc-test"])
        }
        #expect(saved.saved == ["FIRECRAWL_API_KEY"] && saved.isSet?["FIRECRAWL_API_KEY"] == true)
        #expect(request.url.path == "/api/tools/toolsets/web/env")
        let body = try skillsJSONBody(request)
        let env = try #require(body["env"] as? [String: String])
        #expect(env == ["FIRECRAWL_API_KEY": "fc-test"])
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func postSetupStartsAnActionWithTheKey() async throws {
        let (started, request) = try await skillsRun("action_started") {
            try await $0.runSkillToolsetPostSetup("browser", key: "playwright")
        }
        #expect(started.name == "skills-install-arxiv-1a2b3c4d")
        #expect(request.method == "POST" && request.url.path == "/api/tools/toolsets/browser/post-setup")
        #expect(try skillsJSONBody(request)["key"] as? String == "playwright")
    }
}
