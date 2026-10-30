import Foundation

// Assistant settings (WP-53d): config, memory, voice, curator, workspaces, dashboard look and safety.
// A read follows the shape the testbed recorded under Fixtures/rest, named in its doc comment. Values vary between
// runs, so answers are decoded by type only: ``JSONValue`` is shown as the server sent it, and no field is typed.
// A write, and a call with no recorded answer, is status only: its body is not read, and the page reads its lists
// again. None of those is verified against a server [JT].

private struct SettingsAssistantConfigBody: Encodable, Sendable {
    var config: JSONValue
}

private struct SettingsAssistantProviderBody: Encodable, Sendable {
    var provider: String
}

private struct SettingsAssistantValuesBody: Encodable, Sendable {
    var values: [String: JSONValue]
}

private struct SettingsAssistantResetBody: Encodable, Sendable {
    var target: String
}

private struct SettingsAssistantPauseBody: Encodable, Sendable {
    var paused: Bool
}

private struct SettingsAssistantThemeBody: Encodable, Sendable {
    var name: String
}

private struct SettingsAssistantFontBody: Encodable, Sendable {
    var font: String
}

private struct SettingsAssistantConsentBody: Encodable, Sendable {
    var enabled: Bool
    var send: Bool
}

/// A path with each part percent-encoded, so a name such as `a/b` stays one segment.
private func settingsAssistantPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

// MARK: - Config

extension RESTClient {
    /// `GET /api/config`: the config document itself, an object. Recorded in `Fixtures/rest/GET_api_config.json`.
    public func assistantConfig() async throws -> JSONValue {
        try await get("/api/config")
    }

    /// `GET /api/config/schema`. Recorded in `Fixtures/rest/GET_api_config_schema.json`. No page shows it yet.
    public func assistantConfigSchema() async throws -> JSONValue {
        try await get("/api/config/schema")
    }

    /// `GET /api/config/defaults`. Recorded in `Fixtures/rest/GET_api_config_defaults.json`. Not scoped to a profile,
    /// because the OpenAPI gives it no `profile` parameter.
    public func assistantConfigDefaults() async throws -> JSONValue {
        try await get("/api/config/defaults", scoped: false)
    }

    /// Reads the config document, applies `change`, and writes the whole document back with `PUT /api/config`.
    ///
    /// The document sent is the one the read returned, so the write carries every key the read showed. `change` only
    /// touches the keys it names. The query `preserve_language=true` is sent; its effect is not verified [JT]. Whether
    /// the server stores keys that equal its defaults is not verified [JT]. The write is status only. Returns the
    /// document sent. When the read is not a JSON object, throws ``SettingsAssistantConfigError`` before anything is
    /// written.
    @discardableResult
    public func editAssistantConfig(
        _ change: @Sendable (inout SettingsAssistantConfig) throws -> Void
    ) async throws -> SettingsAssistantConfig {
        var config = try SettingsAssistantConfig(answer: try await assistantConfig())
        try change(&config)
        let body = SettingsAssistantConfigBody(config: config.document)
        let _: HTTPResponse = try await send(
            "PUT", "/api/config", query: [URLQueryItem(name: "preserve_language", value: "true")], body: body)
        return config
    }
}

// MARK: - Memory

extension RESTClient {
    /// `GET /api/memory`: the memory providers and the built-in memory files.
    /// Recorded in `Fixtures/rest/GET_api_memory.json`.
    public func assistantMemory() async throws -> JSONValue {
        try await get("/api/memory")
    }

    /// `PUT /api/memory/provider`: makes `provider` the memory provider. Status only. Not recorded [JT].
    public func setAssistantMemoryProvider(_ provider: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/memory/provider", body: SettingsAssistantProviderBody(provider: provider))
    }

    /// `GET /api/memory/providers/{name}/config`. Recorded for `byterover` only, in
    /// `Fixtures/rest/GET_api_memory_providers_byterover_config.json`.
    public func assistantMemoryProviderConfig(_ name: String) async throws -> JSONValue {
        try await get("/api/memory/providers/" + settingsAssistantPath(name, "config"), encodedPath: true)
    }

    /// `PUT /api/memory/providers/{name}/config`: saves the provider's `values`. Status only. Not recorded [JT].
    public func saveAssistantMemoryProviderConfig(_ name: String, values: [String: JSONValue]) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/memory/providers/" + settingsAssistantPath(name, "config"),
            body: SettingsAssistantValuesBody(values: values), encodedPath: true)
    }

    /// `POST /api/memory/providers/{name}/setup` with `values`. Status only. Not recorded [JT].
    public func setupAssistantMemoryProvider(_ name: String, values: [String: JSONValue]) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/memory/providers/" + settingsAssistantPath(name, "setup"),
            body: SettingsAssistantValuesBody(values: values), encodedPath: true)
    }

    /// `POST /api/memory/providers/{provider}/oauth/start`. Status only. Not recorded [JT].
    public func startAssistantMemoryOAuth(_ provider: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/memory/providers/" + settingsAssistantPath(provider, "oauth", "start"), encodedPath: true)
    }

    /// `GET /api/memory/providers/{provider}/oauth/status`. Status only. The testbed recorded a 404 for `byterover`
    /// (`Fixtures/rest/GET_api_memory_providers_byterover_oauth_status.json`) and no 200 answer.
    /// So the body is not read.
    public func assistantMemoryOAuthStatus(_ provider: String) async throws {
        let _: HTTPResponse = try await send(
            "GET", "/api/memory/providers/" + settingsAssistantPath(provider, "oauth", "status"), encodedPath: true)
    }

    /// `POST /api/memory/reset`. `target` is the schema's default, `all`. Destructive: confirm before calling.
    /// Status only. Not recorded [JT].
    public func resetAssistantMemory(target: String = "all") async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/memory/reset", body: SettingsAssistantResetBody(target: target))
    }
}

// MARK: - Voice, curator, workspaces

extension RESTClient {
    /// `GET /api/audio/voice-config`. Recorded in `Fixtures/rest/GET_api_audio_voice-config.json`.
    public func assistantVoiceConfig() async throws -> JSONValue {
        try await get("/api/audio/voice-config")
    }

    /// `GET /api/audio/elevenlabs/voices`. Recorded in `Fixtures/rest/GET_api_audio_elevenlabs_voices.json`.
    /// The recorded run listed no voice, so the fields of a voice are not evidenced.
    public func assistantElevenLabsVoices() async throws -> JSONValue {
        try await get("/api/audio/elevenlabs/voices")
    }

    /// `GET /api/curator`. Recorded in `Fixtures/rest/GET_api_curator.json`.
    public func assistantCurator() async throws -> JSONValue {
        try await get("/api/curator")
    }

    /// `PUT /api/curator/paused`. Status only. Not recorded [JT].
    public func setAssistantCuratorPaused(_ paused: Bool) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/curator/paused", body: SettingsAssistantPauseBody(paused: paused))
    }

    /// `POST /api/curator/run`. Status only. Not recorded [JT].
    public func runAssistantCurator() async throws {
        let _: HTTPResponse = try await send("POST", "/api/curator/run")
    }

    /// `GET /api/chat/workspaces`. Recorded in `Fixtures/rest/GET_api_chat_workspaces.json`. Its `projects` list is
    /// empty in that run, so the fields of a project are not evidenced.
    public func assistantWorkspaces() async throws -> JSONValue {
        try await get("/api/chat/workspaces")
    }

    /// `GET /api/chat/workspaces?scan=true`: asks the server to look for workspaces again. No scan is recorded, so
    /// the answer is not read. The page reads the list again with ``assistantWorkspaces()``.
    /// Status only. Not recorded [JT].
    public func scanAssistantWorkspaces() async throws {
        let _: HTTPResponse = try await send(
            "GET", "/api/chat/workspaces", query: [URLQueryItem(name: "scan", value: "true")])
    }
}

// MARK: - Dashboard look

extension RESTClient {
    /// `GET /api/dashboard/themes`: the server dashboard's themes, for desktop parity.
    /// Recorded in `Fixtures/rest/GET_api_dashboard_themes.json`.
    public func assistantDashboardThemes() async throws -> JSONValue {
        try await get("/api/dashboard/themes")
    }

    /// `PUT /api/dashboard/theme`. Status only. Not recorded [JT].
    public func setAssistantDashboardTheme(_ name: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/dashboard/theme", body: SettingsAssistantThemeBody(name: name))
    }

    /// `GET /api/dashboard/font`. Recorded in `Fixtures/rest/GET_api_dashboard_font.json`.
    public func assistantDashboardFont() async throws -> JSONValue {
        try await get("/api/dashboard/font")
    }

    /// `PUT /api/dashboard/font`. Status only. Not recorded [JT].
    public func setAssistantDashboardFont(_ font: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/dashboard/font", body: SettingsAssistantFontBody(font: font))
    }
}

// MARK: - Safety

extension RESTClient {
    /// `GET /api/egress/status`. Recorded in `Fixtures/rest/GET_api_egress_status.json`: one `text` field.
    public func assistantEgressStatus() async throws -> JSONValue {
        try await get("/api/egress/status")
    }

    /// `GET /api/shared-metrics/consent`. Recorded in `Fixtures/rest/GET_api_shared-metrics_consent.json`.
    public func assistantSharedMetricsConsent() async throws -> JSONValue {
        try await get("/api/shared-metrics/consent")
    }

    /// `PUT /api/shared-metrics/consent`. Sends `send` as false, the schema's default. Status only. Not recorded [JT].
    public func setAssistantSharedMetricsConsent(enabled: Bool) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/shared-metrics/consent", body: SettingsAssistantConsentBody(enabled: enabled, send: false))
    }

    /// `POST /api/ops/security-audit`. Not in `Fixtures/rest/index.json`, so no answer is recorded. Status only. [JT]
    public func runAssistantSecurityAudit() async throws {
        let _: HTTPResponse = try await send("POST", "/api/ops/security-audit")
    }
}
