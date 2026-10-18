import Foundation
import HermesKit
import Testing

/// Each test scripts the answers the server gives and checks the request the client built. No answer is decoded yet,
/// so a call that succeeds is checked by its HTTP status.
@Suite struct ToolsetEndpointTests {
    private func jsonObject(_ request: HTTPRequest) throws -> [String: Any] {
        try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
    }

    @Test func toggleSendsOnlyTheFlag() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200, #"{"ok":true,"name":"browser","platform":"cli","enabled":true,"post_setup_started":"browser"}"#)
        try await makeClient(http).setToolsetEnabled("browser", enabled: true)
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/browser")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["enabled"] as? Bool == true)
    }

    @Test func saveEnvSendsOnlyTheEnteredKeys() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"ok":true,"name":"web","saved":["FIRECRAWL_API_KEY"],"skipped":[],"is_set":{"FIRECRAWL_API_KEY":true}}"#)
        try await makeClient(http).saveToolsetEnv("web", env: ["FIRECRAWL_API_KEY": "fc-test"])
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/web/env")
        let body = try jsonObject(request)
        #expect(body.count == 1 && body["env"] as? [String: String] == ["FIRECRAWL_API_KEY": "fc-test"])
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

    @Test func selectProviderSendsTheCapability() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"ok":true,"name":"web","provider":"Nous Subscription","capability":"search","needs_nous_auth":true,"feature":"web"}"#
        )
        try await makeClient(http).selectToolsetProvider("web", provider: "Nous Subscription", capability: "search")
        let request = try #require(http.requests.first)
        #expect(request.method == "PUT" && request.url.path == "/api/tools/toolsets/web/provider")
        let body = try jsonObject(request)
        #expect(body["provider"] as? String == "Nous Subscription" && body["capability"] as? String == "search")
    }

    @Test func selectProviderWithoutCapabilityOmitsIt() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"image_gen","provider":"FAL"}"#)
        try await makeClient(http).selectToolsetProvider("image_gen", provider: "FAL")
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
        http.enqueue(200)
        try await makeClient(http).setToolsetEnabled("a/b", enabled: false)
        #expect(http.requests.first?.url.path == "/api/tools/toolsets/a%2Fb")
    }
}
