import Foundation
import HermesKit
import Testing

/// Computer Use status is read-only: one GET, decoded from the recorded answer.
@Suite struct CapabilityEndpointTests {
    @Test func computerUseStatusDecodesTheRecordedAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try recordedBody("GET_api_tools_computer-use_status"))
        let status = try await makeClient(http).capabilityComputerUseStatus()
        #expect(status.platform != nil && status.platformSupported != nil && status.installed != nil)
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/tools/computer-use/status")
        #expect(request.url.query == nil)
    }
}
