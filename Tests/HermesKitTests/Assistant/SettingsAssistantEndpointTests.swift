import Foundation
import HermesKit
import Testing

/// Each test checks the method, path, query and body the assistant settings calls send, through the fake transport.
/// Response bodies are canned. Where one copies a recorded fixture under Fixtures/rest, its keys and types match it.
/// No test treats a recorded value as fixed, because values vary between runs.
@Suite struct SettingsAssistantEndpointTests {
    /// The JSON object a request carried.
    private func object(_ request: HTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func readsAreGetsOnTheirPathsAndScope() async throws {
        let http = FakeHTTP()
        for _ in 0..<15 { http.enqueue(200, "{}") }
        let client = makeClient(http, profile: "ops")
        _ = try await client.assistantConfig()
        _ = try await client.assistantConfigSchema()
        _ = try await client.assistantConfigDefaults()
        _ = try await client.assistantMemory()
        _ = try await client.assistantMemoryProviderConfig("byterover")
        try await client.assistantMemoryOAuthStatus("byterover")
        _ = try await client.assistantVoiceConfig()
        _ = try await client.assistantElevenLabsVoices()
        _ = try await client.assistantCurator()
        _ = try await client.assistantWorkspaces()
        try await client.scanAssistantWorkspaces()
        _ = try await client.assistantDashboardThemes()
        _ = try await client.assistantDashboardFont()
        _ = try await client.assistantEgressStatus()
        _ = try await client.assistantSharedMetricsConsent()
        let requests = http.requests
        #expect(requests.allSatisfy { $0.method == "GET" && $0.body == nil })
        #expect(
            requests.map(\.url.path) == [
                "/api/config", "/api/config/schema", "/api/config/defaults", "/api/memory",
                "/api/memory/providers/byterover/config", "/api/memory/providers/byterover/oauth/status",
                "/api/audio/voice-config", "/api/audio/elevenlabs/voices", "/api/curator", "/api/chat/workspaces",
                "/api/chat/workspaces", "/api/dashboard/themes", "/api/dashboard/font", "/api/egress/status",
                "/api/shared-metrics/consent",
            ])
        #expect(
            requests.map(\.url.query) == [
                "profile=ops", "profile=ops", nil, "profile=ops", "profile=ops", "profile=ops", "profile=ops",
                "profile=ops", "profile=ops", "profile=ops", "scan=true&profile=ops", "profile=ops", "profile=ops",
                "profile=ops", "profile=ops",
            ])
    }

    @Test func writesUseTheirMethodsPathsAndBodies() async throws {
        let http = FakeHTTP()
        for _ in 0..<11 { http.enqueue(200, "") }
        let client = makeClient(http)
        try await client.setAssistantMemoryProvider("byterover")
        try await client.saveAssistantMemoryProviderConfig("byterover", values: ["auto_extract": "false"])
        try await client.setupAssistantMemoryProvider("byterover", values: [:])
        try await client.startAssistantMemoryOAuth("byterover")
        try await client.resetAssistantMemory()
        try await client.setAssistantCuratorPaused(true)
        try await client.runAssistantCurator()
        try await client.setAssistantDashboardTheme("midnight")
        try await client.setAssistantDashboardFont("theme")
        try await client.setAssistantSharedMetricsConsent(enabled: true)
        try await client.runAssistantSecurityAudit()
        let requests = http.requests
        #expect(
            requests.map(\.method) == [
                "PUT", "PUT", "POST", "POST", "POST", "PUT", "POST", "PUT", "PUT", "PUT", "POST",
            ])
        #expect(
            requests.map(\.url.path) == [
                "/api/memory/provider", "/api/memory/providers/byterover/config",
                "/api/memory/providers/byterover/setup", "/api/memory/providers/byterover/oauth/start",
                "/api/memory/reset", "/api/curator/paused", "/api/curator/run", "/api/dashboard/theme",
                "/api/dashboard/font", "/api/shared-metrics/consent", "/api/ops/security-audit",
            ])
        #expect(requests.allSatisfy { $0.url.query == nil })

        let provider = try object(requests[0])
        #expect(provider["provider"] as? String == "byterover")
        let config = try object(requests[1])
        #expect((config["values"] as? [String: Any])?["auto_extract"] as? String == "false")
        let setup = try object(requests[2])
        #expect((setup["values"] as? [String: Any])?.isEmpty == true)
        #expect(requests[3].body == nil)
        let reset = try object(requests[4])
        #expect(reset["target"] as? String == "all")
        let pause = try object(requests[5])
        #expect(pause["paused"] as? Bool == true)
        #expect(requests[6].body == nil)
        let theme = try object(requests[7])
        #expect(theme["name"] as? String == "midnight")
        let font = try object(requests[8])
        #expect(font["font"] as? String == "theme")
        let consent = try object(requests[9])
        #expect(consent["enabled"] as? Bool == true)
        #expect(consent["send"] as? Bool == false)
        #expect(requests[10].body == nil)
    }

    @Test func aFailedWriteThrowsTheServersDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(400, #"{"detail":"identifier is required"}"#)
        let client = makeClient(http)
        await #expect(throws: RESTError.http(status: 400, detail: "identifier is required")) {
            try await client.setAssistantCuratorPaused(true)
        }
    }

    @Test func statusOnlyCallsIgnoreTheBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "Scan started")
        http.enqueue(200, "")
        let client = makeClient(http)
        try await client.scanAssistantWorkspaces()
        try await client.runAssistantSecurityAudit()
        #expect(http.requests.count == 2)
    }

    @Test func recordedAnswersAreKeptAsTheServerSentThem() async throws {
        let http = FakeHTTP()
        // A canned excerpt in the shape of GET_api_egress_status.json, with its line breaks.
        http.enqueue(200, #"{"text":"Egress proxy status\n\nEnabled: no\nBinary: (missing)"}"#)
        http.enqueue(200, #"{"decided":false,"enabled":false,"managed":false,"reask":false,"send":false}"#)
        let client = makeClient(http)
        let egress = try await client.assistantEgressStatus()
        #expect(egress == ["text": "Egress proxy status\n\nEnabled: no\nBinary: (missing)"])
        let consent = try await client.assistantSharedMetricsConsent()
        #expect(consent == ["decided": false, "enabled": false, "managed": false, "reask": false, "send": false])
    }

    @Test func namesStayOnePathSegment() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        let client = makeClient(http)
        _ = try await client.assistantMemoryProviderConfig("a/b c")
        #expect(http.requests.first?.url.path == "/api/memory/providers/a%2Fb%20c/config")
    }

    @Test func editingOneKeyWritesEveryOtherKeyBack() async throws {
        let http = FakeHTTP()
        // Trimmed from GET_api_config.json: the keys and their types are recorded there. Values are canned.
        http.enqueue(
            200,
            #"{"voice":{"auto_tts":false,"barge_in":true,"beep_volume":0.3},"model":"fake-model","#
                + #""terminal":{"backend":"local","cwd":".","timeout":180},"#
                + #""curator":{"enabled":true,"interval_hours":168}}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        let saved = try await client.editAssistantConfig { config in
            try config.set(.bool(true), at: ["voice", "auto_tts"])
        }
        #expect(saved.value(at: ["voice", "auto_tts"]) == .bool(true))
        let requests = http.requests
        #expect(requests.count == 2)
        #expect(requests.first?.method == "GET")
        #expect(requests.first?.url.query == "profile=ops")
        let put = try #require(requests.last)
        #expect(put.method == "PUT" && put.url.path == "/api/config")
        #expect(put.url.query == "preserve_language=true&profile=ops")
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(put.body))
        let expected: JSONValue = [
            "voice": ["auto_tts": true, "barge_in": true, "beep_volume": 0.3],
            "model": "fake-model",
            "terminal": ["backend": "local", "cwd": ".", "timeout": 180],
            "curator": ["enabled": true, "interval_hours": 168],
        ]
        #expect(sent["config"] == expected)
    }

    @Test func aNonObjectConfigAnswerIsNeverWritten() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "[1,2]")
        let client = makeClient(http)
        await #expect(throws: SettingsAssistantConfigError.notAnObject(path: [])) {
            try await client.editAssistantConfig { _ in }
        }
        #expect(http.requests.count == 1)
    }
}
