import Foundation

private struct ToolsetToggleBody: Encodable, Sendable {
    var enabled: Bool
}

private struct ToolsetModelBody: Encodable, Sendable {
    var model: String
    var provider: String?
}

private struct ToolsetProviderBody: Encodable, Sendable {
    var provider: String
    var capability: String?
}

private struct ToolsetEnvBody: Encodable, Sendable {
    var env: [String: String]
}

private struct ToolsetPostSetupBody: Encodable, Sendable {
    var key: String
}

/// Toolset calls. The list itself is ``RESTClient/toolsets()``. Every call is scoped to the active profile by ``RESTClient``.
extension RESTClient {
    /// `PUT /api/tools/toolsets/{name}`: turns a toolset on or off for its configuration platform.
    public func setSkillToolsetEnabled(_ name: String, enabled: Bool) async throws -> ToolsetToggleResult {
        try await send("PUT", "/api/tools/toolsets/" + restPathSegment(name), body: ToolsetToggleBody(enabled: enabled))
    }

    /// `GET /api/tools/toolsets/{name}/config`: the provider picker and which keys are set.
    public func skillToolsetConfig(_ name: String) async throws -> SkillToolsetConfig {
        try await get("/api/tools/toolsets/" + restPathSegment(name) + "/config")
    }

    /// `GET /api/tools/toolsets/{name}/models`. `provider` names a picker row; nil means the active one.
    public func skillToolsetModels(_ name: String, provider: String? = nil) async throws -> SkillToolsetModelCatalog {
        try await get(
            "/api/tools/toolsets/" + restPathSegment(name) + "/models",
            query: provider.map { [URLQueryItem(name: "provider", value: $0)] } ?? [])
    }

    /// `PUT /api/tools/toolsets/{name}/model`: picks a model from the catalog of the backend.
    public func selectSkillToolsetModel(
        _ name: String, model: String, provider: String? = nil
    ) async throws -> ToolsetModelSelection {
        try await send(
            "PUT", "/api/tools/toolsets/" + restPathSegment(name) + "/model",
            body: ToolsetModelBody(model: model, provider: provider))
    }

    /// `PUT /api/tools/toolsets/{name}/provider`. `capability` (`search` or `extract`) applies to the web toolset only.
    public func selectSkillToolsetProvider(
        _ name: String, provider: String, capability: String? = nil
    ) async throws -> ToolsetProviderSelection {
        try await send(
            "PUT", "/api/tools/toolsets/" + restPathSegment(name) + "/provider",
            body: ToolsetProviderBody(provider: provider, capability: capability))
    }

    /// `PUT /api/tools/toolsets/{name}/env`: saves provider keys. Only the toolset's own variable names are accepted.
    public func saveSkillToolsetEnv(_ name: String, env: [String: String]) async throws -> ToolsetEnvSaved {
        try await send("PUT", "/api/tools/toolsets/" + restPathSegment(name) + "/env", body: ToolsetEnvBody(env: env))
    }

    /// `POST /api/tools/toolsets/{name}/post-setup`: starts a provider's install in the background. Poll the action.
    public func runSkillToolsetPostSetup(_ name: String, key: String) async throws -> ServerActionStart {
        try await send(
            "POST", "/api/tools/toolsets/" + restPathSegment(name) + "/post-setup", body: ToolsetPostSetupBody(key: key)
        )
    }
}
