import Foundation
import HermesKit
import Testing

/// Each test checks the method, path, query and body the assistant settings calls send, through the fake transport.
@Suite struct SettingsAssistantEndpointTests {
    /// The JSON object a request carried.
    private func object(_ request: HTTPRequest) throws -> [String: Any] {
        let body = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func readsAreGetsOnTheirPathsAndScope() async throws {
        let http = FakeHTTP()
        for _ in 0..<15 { http.enqueue(200, #"{"ok":true}"#) }
        let client = makeClient(http, profile: "ops")
        _ = try await client.assistantConfig()
        _ = try await client.assistantConfig(includeDefaults: false)
        _ = try await client.assistantConfigSchema()
        _ = try await client.assistantConfigDefaults()
        _ = try await client.assistantMemory()
        _ = try await client.assistantMemoryProviderConfig("mem0", surface: "cli")
        _ = try await client.assistantMemoryOAuthStatus("nous")
        _ = try await client.assistantVoiceConfig()
        _ = try await client.assistantElevenLabsVoices()
        _ = try await client.assistantCurator()
        _ = try await client.assistantWorkspaces(scan: true)
        _ = try await client.assistantDashboardThemes()
        _ = try await client.assistantDashboardFont()
        _ = try await client.assistantEgressStatus()
        _ = try await client.assistantSharedMetricsConsent()
        let requests = http.requests
        #expect(requests.allSatisfy { $0.method == "GET" && $0.body == nil })
        #expect(
            requests.map(\.url.path) == [
                "/api/config", "/api/config", "/api/config/schema", "/api/config/defaults", "/api/memory",
                "/api/memory/providers/mem0/config", "/api/memory/providers/nous/oauth/status",
                "/api/audio/voice-config", "/api/audio/elevenlabs/voices", "/api/curator", "/api/chat/workspaces",
                "/api/dashboard/themes", "/api/dashboard/font", "/api/egress/status", "/api/shared-metrics/consent",
            ])
        #expect(
            requests.map(\.url.query) == [
                "profile=ops", "include_defaults=false&profile=ops", "profile=ops", nil, "profile=ops",
                "surface=cli&profile=ops", "profile=ops", "profile=ops", "profile=ops", "profile=ops",
                "scan=true&profile=ops", "profile=ops", "profile=ops", "profile=ops", "profile=ops",
            ])
    }

    @Test func writesUseTheirMethodsPathsAndBodies() async throws {
        let http = FakeHTTP()
        for _ in 0..<11 { http.enqueue(200, "") }
        let client = makeClient(http)
        try await client.setAssistantMemoryProvider("honcho")
        try await client.saveAssistantMemoryProviderConfig(
            "honcho", values: ["api_url": "https://example.com"], surface: "gw")
        _ = try await client.setupAssistantMemoryProvider("honcho", values: [:])
        _ = try await client.startAssistantMemoryOAuth("nous")
        _ = try await client.resetAssistantMemory()
        try await client.setAssistantCuratorPaused(true)
        _ = try await client.runAssistantCurator()
        try await client.setAssistantDashboardTheme("midnight")
        try await client.setAssistantDashboardFont("mono")
        try await client.setAssistantSharedMetricsConsent(enabled: true)
        _ = try await client.runAssistantSecurityAudit()
        let requests = http.requests
        #expect(
            requests.map(\.method) == [
                "PUT", "PUT", "POST", "POST", "POST", "PUT", "POST", "PUT", "PUT", "PUT", "POST",
            ])
        #expect(
            requests.map(\.url.path) == [
                "/api/memory/provider", "/api/memory/providers/honcho/config", "/api/memory/providers/honcho/setup",
                "/api/memory/providers/nous/oauth/start", "/api/memory/reset", "/api/curator/paused",
                "/api/curator/run", "/api/dashboard/theme", "/api/dashboard/font", "/api/shared-metrics/consent",
                "/api/ops/security-audit",
            ])
        #expect(requests.map(\.url.query) == [nil, "surface=gw", nil, nil, nil, nil, nil, nil, nil, nil, nil])

        let provider = try object(requests[0])
        #expect(provider["provider"] as? String == "honcho")
        let config = try object(requests[1])
        #expect((config["values"] as? [String: Any])?["api_url"] as? String == "https://example.com")
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
        #expect(font["font"] as? String == "mono")
        let consent = try object(requests[9])
        #expect(consent["enabled"] as? Bool == true)
        #expect(consent["send"] as? Bool == false)
        #expect(requests[10].body == nil)
    }

    @Test func answersAreKeptAsTheServerSentThem() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"enabled":false,"allowed_hosts":["api.example.com"],"Mode":"strict"}"#)
        http.enqueue(200, "Scan started")
        http.enqueue(200, "")
        let client = makeClient(http)
        let egress = try await client.assistantEgressStatus()
        #expect(egress == ["enabled": false, "allowed_hosts": ["api.example.com"], "Mode": "strict"])
        let audit = try await client.runAssistantSecurityAudit()
        #expect(audit == .string("Scan started"))
        let curator = try await client.runAssistantCurator()
        #expect(curator == .null)
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
        http.enqueue(
            200,
            #"{"voice":{"enabled":false,"speed":1.5},"api_keys":{"OPENAI_API_KEY":"sk-x"},"maxTokens":2048,"#
                + #""model":{"default":"fake-model"},"terminal":{"timeout":60,"shell":null}}"#)
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        let saved = try await client.editAssistantConfig { config in
            try config.set(.bool(true), at: ["voice", "enabled"])
        }
        #expect(saved.value(at: ["voice", "enabled"]) == .bool(true))
        let requests = http.requests
        #expect(requests.count == 2)
        #expect(requests.first?.method == "GET")
        #expect(requests.first?.url.query == "include_defaults=false&profile=ops")
        let put = try #require(requests.last)
        #expect(put.method == "PUT" && put.url.path == "/api/config")
        #expect(put.url.query == "preserve_language=true&profile=ops")
        let sent = try JSONDecoder().decode(JSONValue.self, from: try #require(put.body))
        let expected: JSONValue = [
            "voice": ["enabled": true, "speed": 1.5],
            "api_keys": ["OPENAI_API_KEY": "sk-x"],
            "maxTokens": 2048,
            "model": ["default": "fake-model"],
            "terminal": ["timeout": 60, "shell": nil],
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
