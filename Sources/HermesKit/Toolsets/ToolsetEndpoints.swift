import Foundation

private struct ToolsetToggleBody: Encodable, Sendable {
    var enabled: Bool
}

/// Joins path parts, percent-encoding each one so a name cannot add a path segment.
private func toolsetPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

/// Toolset configuration: switch, provider, keys, models and setup. The list itself is ``RESTClient/toolsets()``.
extension RESTClient {
    /// `PUT /api/tools/toolsets/{name}`: switches a toolset on or off for its configuration platform.
    public func setToolsetEnabled(_ name: String, enabled: Bool) async throws -> ToolsetToggleResult {
        try await send("PUT", "/api/tools/toolsets/" + toolsetPath(name), body: ToolsetToggleBody(enabled: enabled))
    }

    /// `GET /api/tools/toolsets/{name}/config`: the provider rows and which keys are set.
    public func toolsetConfig(_ name: String) async throws -> ToolsetConfig {
        try await get("/api/tools/toolsets/" + toolsetPath(name, "config"))
    }

    /// `PUT /api/tools/toolsets/{name}/env`: stores API keys in `.env`. Keys can only be ones a provider of this
    /// toolset reads. Blank values are left unchanged, so send only the keys the user filled in.
    public func saveToolsetEnv(_ name: String, env: [String: String]) async throws -> ToolsetEnvResult {
        try await send("PUT", "/api/tools/toolsets/" + toolsetPath(name, "env"), body: ToolsetEnvUpdate(env: env))
    }

    /// `GET /api/tools/toolsets/{name}/models`. `provider` names a provider row; nil means the active one.
    public func toolsetModels(_ name: String, provider: String? = nil) async throws -> ToolsetModelCatalog {
        let query = provider.map { [URLQueryItem(name: "provider", value: $0)] } ?? []
        return try await get("/api/tools/toolsets/" + toolsetPath(name, "models"), query: query)
    }

    /// `PUT /api/tools/toolsets/{name}/model`: chooses the model of a media backend.
    public func selectToolsetModel(_ name: String, model: String, provider: String? = nil) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/tools/toolsets/" + toolsetPath(name, "model"),
            body: ToolsetModelSelect(model: model, provider: provider))
    }

    /// `PUT /api/tools/toolsets/{name}/provider`: chooses the provider. `capability` (`search` or `extract`)
    /// applies to the web toolset only.
    public func selectToolsetProvider(
        _ name: String, provider: String, capability: String? = nil
    ) async throws -> ToolsetProviderResult {
        try await send(
            "PUT", "/api/tools/toolsets/" + toolsetPath(name, "provider"),
            body: ToolsetProviderSelect(provider: provider, capability: capability))
    }

    /// `POST /api/tools/toolsets/{name}/post-setup`: starts a provider's install in the background on the server.
    /// The progress endpoint is not read here.
    public func runToolsetPostSetup(_ name: String, key: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/tools/toolsets/" + toolsetPath(name, "post-setup"), body: ToolsetPostSetup(key: key))
    }
}
