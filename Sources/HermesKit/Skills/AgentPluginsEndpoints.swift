import Foundation

private struct AcceptCapabilitiesBody: Encodable, Sendable {
    var acceptCapabilities: Bool
}

private struct ActivateBody: Encodable, Sendable {
    var name: String
    var home: String
}

/// Agent plugin calls: the plugins Hermes loads on the server (not dashboard tabs). Every call is scoped to the active
/// profile by ``RESTClient``, like the other calls. The server runs these against its own profile.
extension RESTClient {
    /// `GET /api/dashboard/plugins/hub`: the discovered agent plugins and whether each is enabled.
    public func agentPluginHub() async throws -> AgentPluginHub {
        try await get("/api/dashboard/plugins/hub")
    }

    /// `GET /api/dashboard/plugins/catalog`: the curated catalog, with the pinned commit and what is installed.
    public func agentPluginCatalog() async throws -> AgentPluginCatalog {
        try await get("/api/dashboard/plugins/catalog")
    }

    /// `GET /api/dashboard/plugins/rescan`: rereads the plugin folders on the server.
    public func rescanAgentPlugins() async throws -> AgentPluginRescan {
        try await get("/api/dashboard/plugins/rescan")
    }

    /// `POST /api/dashboard/agent-plugins/install`: installs from a git URL or a catalog entry, optionally pinned to a commit.
    public func installAgentPlugin(_ request: AgentPluginInstallRequest) async throws -> AgentPluginResult {
        try await send("POST", "/api/dashboard/agent-plugins/install", body: request)
    }

    /// `POST /api/dashboard/agent-plugins/{name}/enable` or `/disable`: the on and off switch.
    public func setAgentPluginEnabled(_ name: String, enabled: Bool) async throws -> AgentPluginResult {
        try await send(
            "POST", "/api/dashboard/agent-plugins/" + restPathSegment(name) + (enabled ? "/enable" : "/disable"),
            encodedPath: true)
    }

    /// `POST /api/dashboard/agent-plugins/{name}/update`: pulls a git install, or moves a catalog install to its new pin.
    /// Pass `acceptCapabilities` only after the user agreed to the delta of a `consentRequired` answer.
    public func updateAgentPlugin(_ name: String, acceptCapabilities: Bool = false) async throws -> AgentPluginResult {
        try await send(
            "POST", "/api/dashboard/agent-plugins/" + restPathSegment(name) + "/update",
            body: AcceptCapabilitiesBody(acceptCapabilities: acceptCapabilities), encodedPath: true)
    }

    /// `DELETE /api/dashboard/agent-plugins/{name}`: deletes a user or git install. Bundled plugins cannot be removed.
    public func removeAgentPlugin(_ name: String) async throws -> AgentPluginResult {
        try await send("DELETE", "/api/dashboard/agent-plugins/" + restPathSegment(name), encodedPath: true)
    }

    /// `POST /api/dashboard/agent-plugins/activate`: asks the server to load the plugin for a profile home, so its open
    /// chats get the plugin's tools now. `home` is the profile's home directory on the server (``HermesProfile/path``).
    public func activateAgentPlugin(_ name: String, home: String) async throws -> AgentPluginResult {
        try await send(
            "POST", "/api/dashboard/agent-plugins/activate", body: ActivateBody(name: name, home: home))
    }
}
