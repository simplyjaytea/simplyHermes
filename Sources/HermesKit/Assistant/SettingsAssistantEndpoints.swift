import Foundation

// Assistant settings (WP-53d): config, memory, voice, curator, workspaces, dashboard look and safety.
// The OpenAPI gives almost every answer here as any JSON (`{}`), so answers come back as ``JSONValue`` and are shown
// as the server sent them. Only request bodies are typed, from the schema.

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

private func settingsAssistantFlag(_ name: String, _ value: Bool?) -> [URLQueryItem] {
    guard let value else { return [] }
    return [URLQueryItem(name: name, value: value ? "true" : "false")]
}

private func settingsAssistantText(_ name: String, _ value: String?) -> [URLQueryItem] {
    guard let value else { return [] }
    return [URLQueryItem(name: name, value: value)]
}

/// The answer of a POST or PUT whose schema gives no shape: its JSON when it parses, its text otherwise, and `null`
/// when the body is empty.
private func settingsAssistantAnswer(_ response: HTTPResponse) -> JSONValue {
    if response.body.isEmpty { return .null }
    if let value = try? JSONDecoder().decode(JSONValue.self, from: response.body) { return value }
    return .string(String(decoding: response.body, as: UTF8.self))
}

// MARK: - Config

extension RESTClient {
    /// `GET /api/config`: the whole config document, as the server sends it. `includeDefaults` overrides the server's
    /// default (true) when set.
    public func assistantConfig(includeDefaults: Bool? = nil) async throws -> JSONValue {
        try await get("/api/config", query: settingsAssistantFlag("include_defaults", includeDefaults))
    }

    /// `GET /api/config/schema`.
    public func assistantConfigSchema() async throws -> JSONValue {
        try await get("/api/config/schema")
    }

    /// `GET /api/config/defaults`. Not scoped to a profile, because the schema gives it no `profile` parameter.
    public func assistantConfigDefaults() async throws -> JSONValue {
        try await get("/api/config/defaults", scoped: false)
    }

    /// Reads the config document, applies `change`, and writes the whole document back with `PUT /api/config`.
    ///
    /// The read asks for the document without defaults (`include_defaults=false`), so the write does not store
    /// the server's default values. `change` only touches the keys it names. `preserve_language` is set so the
    /// server keeps the language as it is. Returns the document that was written. When the answer is not a JSON
    /// object, throws ``SettingsAssistantConfigError`` before anything is written.
    @discardableResult
    public func editAssistantConfig(
        _ change: @Sendable (inout SettingsAssistantConfig) throws -> Void
    ) async throws -> SettingsAssistantConfig {
        var config = try SettingsAssistantConfig(answer: try await assistantConfig(includeDefaults: false))
        try change(&config)
        let body = SettingsAssistantConfigBody(config: config.document)
        let _: HTTPResponse = try await send(
            "PUT", "/api/config", query: [URLQueryItem(name: "preserve_language", value: "true")], body: body)
        return config
    }
}

// MARK: - Memory

extension RESTClient {
    /// `GET /api/memory`: the memory provider and its status.
    public func assistantMemory() async throws -> JSONValue {
        try await get("/api/memory")
    }

    /// `PUT /api/memory/provider`: makes `provider` the memory provider.
    public func setAssistantMemoryProvider(_ provider: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/memory/provider", body: SettingsAssistantProviderBody(provider: provider))
    }

    /// `GET /api/memory/providers/{name}/config`.
    public func assistantMemoryProviderConfig(_ name: String, surface: String? = nil) async throws -> JSONValue {
        try await get(
            "/api/memory/providers/" + settingsAssistantPath(name, "config"),
            query: settingsAssistantText("surface", surface))
    }

    /// `PUT /api/memory/providers/{name}/config`: saves the provider's `values`.
    public func saveAssistantMemoryProviderConfig(
        _ name: String, values: [String: JSONValue], surface: String? = nil
    ) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/memory/providers/" + settingsAssistantPath(name, "config"),
            query: settingsAssistantText("surface", surface), body: SettingsAssistantValuesBody(values: values))
    }

    /// `POST /api/memory/providers/{name}/setup` with `values`. The answer is returned as it came.
    public func setupAssistantMemoryProvider(_ name: String, values: [String: JSONValue]) async throws -> JSONValue {
        let response: HTTPResponse = try await send(
            "POST", "/api/memory/providers/" + settingsAssistantPath(name, "setup"),
            body: SettingsAssistantValuesBody(values: values))
        return settingsAssistantAnswer(response)
    }

    /// `POST /api/memory/providers/{provider}/oauth/start`. The answer is returned as it came.
    public func startAssistantMemoryOAuth(_ provider: String) async throws -> JSONValue {
        let response: HTTPResponse = try await send(
            "POST", "/api/memory/providers/" + settingsAssistantPath(provider, "oauth", "start"))
        return settingsAssistantAnswer(response)
    }

    /// `GET /api/memory/providers/{provider}/oauth/status`.
    public func assistantMemoryOAuthStatus(_ provider: String) async throws -> JSONValue {
        try await get("/api/memory/providers/" + settingsAssistantPath(provider, "oauth", "status"))
    }

    /// `POST /api/memory/reset`. `target` is the schema's default, `all`. Destructive: confirm before calling.
    public func resetAssistantMemory(target: String = "all") async throws -> JSONValue {
        let response: HTTPResponse = try await send(
            "POST", "/api/memory/reset", body: SettingsAssistantResetBody(target: target))
        return settingsAssistantAnswer(response)
    }
}

// MARK: - Voice, curator, workspaces

extension RESTClient {
    /// `GET /api/audio/voice-config`.
    public func assistantVoiceConfig() async throws -> JSONValue {
        try await get("/api/audio/voice-config")
    }

    /// `GET /api/audio/elevenlabs/voices`.
    public func assistantElevenLabsVoices() async throws -> JSONValue {
        try await get("/api/audio/elevenlabs/voices")
    }

    /// `GET /api/curator`.
    public func assistantCurator() async throws -> JSONValue {
        try await get("/api/curator")
    }

    /// `PUT /api/curator/paused`.
    public func setAssistantCuratorPaused(_ paused: Bool) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/curator/paused", body: SettingsAssistantPauseBody(paused: paused))
    }

    /// `POST /api/curator/run`. The answer is returned as it came.
    public func runAssistantCurator() async throws -> JSONValue {
        let response: HTTPResponse = try await send("POST", "/api/curator/run")
        return settingsAssistantAnswer(response)
    }

    /// `GET /api/chat/workspaces`. `scan` asks the server to look for workspaces again when set.
    public func assistantWorkspaces(scan: Bool? = nil) async throws -> JSONValue {
        try await get("/api/chat/workspaces", query: settingsAssistantFlag("scan", scan))
    }
}

// MARK: - Dashboard look

extension RESTClient {
    /// `GET /api/dashboard/themes`: the server dashboard's themes, for desktop parity.
    public func assistantDashboardThemes() async throws -> JSONValue {
        try await get("/api/dashboard/themes")
    }

    /// `PUT /api/dashboard/theme`.
    public func setAssistantDashboardTheme(_ name: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/dashboard/theme", body: SettingsAssistantThemeBody(name: name))
    }

    /// `GET /api/dashboard/font`.
    public func assistantDashboardFont() async throws -> JSONValue {
        try await get("/api/dashboard/font")
    }

    /// `PUT /api/dashboard/font`.
    public func setAssistantDashboardFont(_ font: String) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/dashboard/font", body: SettingsAssistantFontBody(font: font))
    }
}

// MARK: - Safety

extension RESTClient {
    /// `GET /api/egress/status`.
    public func assistantEgressStatus() async throws -> JSONValue {
        try await get("/api/egress/status")
    }

    /// `GET /api/shared-metrics/consent`.
    public func assistantSharedMetricsConsent() async throws -> JSONValue {
        try await get("/api/shared-metrics/consent")
    }

    /// `PUT /api/shared-metrics/consent`. Sends the schema's default for `send`, false.
    public func setAssistantSharedMetricsConsent(enabled: Bool) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/shared-metrics/consent", body: SettingsAssistantConsentBody(enabled: enabled, send: false))
    }

    /// `POST /api/ops/security-audit`. The answer is returned as it came, to show to the user.
    public func runAssistantSecurityAudit() async throws -> JSONValue {
        let response: HTTPResponse = try await send("POST", "/api/ops/security-audit")
        return settingsAssistantAnswer(response)
    }
}
