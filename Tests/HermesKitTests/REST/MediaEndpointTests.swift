import Foundation
import HermesKit
import Testing

@Suite struct MediaEndpointTests {
    @Test func fetchesAMediaPath() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "PNG")
        let data = try await makeClient(http).mediaFile(path: "/opt/hermes/cache/out.png")

        #expect(data == Data("PNG".utf8))
        #expect(http.requests.first?.url.query == "path=/opt/hermes/cache/out.png")
    }

    @Test func proxiesARemoteImage() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "GIF")
        _ = try await makeClient(http).proxiedMedia(url: "https://images.example/cat.gif")

        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/media/proxy")
        #expect(request.url.query == "url=https://images.example/cat.gif")
    }
}
