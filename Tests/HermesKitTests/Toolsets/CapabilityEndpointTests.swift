import Foundation
import HermesKit
import Testing

/// Computer Use status is read-only: one GET, decoded for display.
@Suite struct CapabilityEndpointTests {
    @Test func computerUseStatusDecodesTheProbes() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"platform":"darwin","platform_supported":true,"installed":true,"version":"0.4.2","ready":false,
             "can_grant":true,"checks":[{"label":"Driver","status":"ok","message":"running"}],
             "source":{"kind":"bundle"},"error":null,"accessibility":true,"screen_recording":false,
             "screen_recording_capturable":null,"future":1}
            """#)
        let status = try await makeClient(http).capabilityComputerUseStatus()
        #expect(status.platform == "darwin" && status.platformSupported == true && status.installed == true)
        #expect(status.version == "0.4.2" && status.ready == false && status.canGrant == true)
        #expect(status.accessibility == true && status.screenRecording == false)
        #expect(status.screenRecordingCapturable == nil && status.error == nil)
        #expect(status.checks?.first?.label == "Driver" && status.checks?.first?.message == "running")
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/tools/computer-use/status")
        #expect(request.url.query == nil)
    }

    @Test func unknownReadinessStaysNil() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"platform":"linux","platform_supported":true,"installed":false,"ready":null}"#)
        let status = try await makeClient(http).capabilityComputerUseStatus()
        #expect(status.ready == nil && status.installed == false && status.checks == nil)
    }
}
