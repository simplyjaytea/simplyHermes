import Foundation
import HermesKit
import Testing

/// Each test scripts the answers the server gives and checks the request the client built and the decoded values.
@Suite struct ToolsetEndpointTests {
    private static let webConfigJSON = #"""
        {"name":"web","has_category":true,
         "providers":[{"name":"Firecrawl","badge":"paid","tag":"","env_vars":[{"key":"FIRECRAWL_API_KEY",
           "prompt":"Firecrawl API key","url":"https://example.com/keys","default":null,"is_set":false}],
           "post_setup":null,"requires_nous_auth":false,"managed_nous_feature":null,"is_active":true,
           "status":"needs_keys","web_backend":"firecrawl","capabilities":["search","extract"]}],
         "active_provider":"Firecrawl","active_search_backend":"firecrawl","active_extract_backend":"firecrawl",
         "search_via_nous":false,"extract_via_nous":false}
        """#

    private func jsonObject(_ request: HTTPRequest) throws -> [String: Any] {
        try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    }

    @Test func toggleSendsOnlyTheFlagAndReportsSetup() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200, #"{"ok":true,"name":"browser","platform":"cli","enabled":true,"post_setup_started":"browser"}"#)
        let result = try await makeClient(http).setToolsetEnabled("browser", enabled: true)
        #expect(result.enabled == true && result.platform == "cli" && result.postSetupStarted == "browser")
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/browser")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["enabled"] as? Bool == true)
    }

    @Test func configDecodesProvidersAndKeyState() async throws {
        let http = FakeHTTP()
        http.enqueue(200, Self.webConfigJSON)
        let config = try await makeClient(http).toolsetConfig("web")
        #expect(config.hasCategory == true && config.activeProvider == "Firecrawl")
        let provider = try #require(config.providers?.first)
        #expect(
            provider.status == "needs_keys" && provider.isActive == true
                && provider.capabilities == ["search", "extract"])
        #expect(provider.envVars?.first?.key == "FIRECRAWL_API_KEY" && provider.envVars?.first?.isSet == false)
        #expect(provider.id == "Firecrawl" && provider.envVars?.first?.id == "FIRECRAWL_API_KEY")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/tools/toolsets/web/config")
    }

    @Test func configForAToolsetWithoutCategoryDecodes() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"name":"skills","has_category":false,"providers":[],"active_provider":null}"#)
        let config = try await makeClient(http).toolsetConfig("skills")
        #expect(config.hasCategory == false && config.providers?.isEmpty == true && config.activeProvider == nil)
    }

    @Test func saveEnvSendsOnlyTheEnteredKeys() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"ok":true,"name":"web","saved":["FIRECRAWL_API_KEY"],"skipped":[],"is_set":{"FIRECRAWL_API_KEY":true}}"#)
        let result = try await makeClient(http).saveToolsetEnv("web", env: ["FIRECRAWL_API_KEY": "fc-test"])
        #expect(result.saved == ["FIRECRAWL_API_KEY"] && result.skipped?.isEmpty == true)
        #expect(result.isSet?["FIRECRAWL_API_KEY"] == true)
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/web/env")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["env"] as? [String: String] == ["FIRECRAWL_API_KEY": "fc-test"])
    }

    @Test func modelsDecodeWithTheProviderQuery() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"name":"image_gen","has_models":true,"provider":"FAL","plugin":"fal","models":[{"id":"flux-1","display":"Flux","speed":"fast","strengths":"detail","price":"$"}],"current":"flux-1","default":"flux-1"}"#
        )
        let catalog = try await makeClient(http).toolsetModels("image_gen", provider: "FAL")
        #expect(catalog.hasModels == true && catalog.provider == "FAL" && catalog.defaultModel == "flux-1")
        #expect(catalog.models?.first?.id == "flux-1" && catalog.models?.first?.display == "Flux")
        #expect(catalog.current == "flux-1")
        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/tools/toolsets/image_gen/models" && request.url.query == "provider=FAL")
    }

    @Test func modelsWithoutACatalogDecodeAsEmpty() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"name":"web","has_models":false,"models":[],"current":null,"default":null}"#)
        let catalog = try await makeClient(http).toolsetModels("web")
        #expect(catalog.hasModels == false && catalog.models?.isEmpty == true && catalog.defaultModel == nil)
        #expect(http.requests.first?.url.query == nil)
    }

    @Test func selectModelOmitsProviderWhenNotGiven() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"image_gen","model":"flux-1","plugin":"fal"}"#)
        try await makeClient(http).selectToolsetModel("image_gen", model: "flux-1")
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/image_gen/model")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["model"] as? String == "flux-1")
    }

    @Test func selectProviderSendsCapabilityAndReadsTheNousFlag() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"ok":true,"name":"web","provider":"Nous Subscription","capability":"search","needs_nous_auth":true,"feature":"web"}"#
        )
        let result = try await makeClient(http).selectToolsetProvider(
            "web", provider: "Nous Subscription", capability: "search")
        #expect(result.needsNousAuth == true && result.feature == "web" && result.capability == "search")
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/web/provider")
        let body = try jsonObject(request)
        #expect(body["provider"] as? String == "Nous Subscription" && body["capability"] as? String == "search")
    }

    @Test func selectProviderWithoutCapabilityOmitsIt() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"image_gen","provider":"FAL"}"#)
        let result = try await makeClient(http).selectToolsetProvider("image_gen", provider: "FAL")
        #expect(result.ok == true && result.needsNousAuth == nil)
        let body = try jsonObject(try #require(http.requests.first))
        #expect(body.count == 1 && body["provider"] as? String == "FAL")
    }

    @Test func postSetupStartsTheKeyInTheBackground() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"key":"cua-driver"}"#)
        try await makeClient(http).runToolsetPostSetup("computer_use", key: "cua-driver")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/tools/toolsets/computer_use/post-setup")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["key"] as? String == "cua-driver")
    }

    @Test func toolsetNameIsEncodedInThePath() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"name":"a/b","has_category":false,"providers":[],"active_provider":null}"#)
        _ = try await makeClient(http).toolsetConfig("a/b")
        #expect(http.requests.first?.url.path == "/api/tools/toolsets/a%2Fb/config")
    }
}
