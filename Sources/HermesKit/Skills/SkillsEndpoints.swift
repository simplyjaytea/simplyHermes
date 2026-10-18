import Foundation

private struct SkillToggleBody: Encodable, Sendable {
    var name: String
    var enabled: Bool
}

private struct SkillNameBody: Encodable, Sendable {
    var name: String
}

private struct SkillContentBody: Encodable, Sendable {
    var name: String
    var content: String
}

private struct SkillCreateBody: Encodable, Sendable {
    var name: String
    var content: String
    var category: String?
}

private struct SkillIdentifierBody: Encodable, Sendable {
    var identifier: String
}

/// Skill calls. The list itself is ``RESTClient/skills()``. Every call here is scoped to the active profile by
/// ``RESTClient``, the same way the other profile calls are.
extension RESTClient {
    /// `PUT /api/skills/toggle`: turns a skill on or off for the profile.
    public func setSkillEnabled(_ name: String, enabled: Bool) async throws -> SkillToggleResult {
        try await send("PUT", "/api/skills/toggle", body: SkillToggleBody(name: name, enabled: enabled))
    }

    /// `GET /api/skills/content?name=`: the SKILL.md text of an installed skill.
    public func skillContent(_ name: String) async throws -> SkillContent {
        try await get("/api/skills/content", query: [URLQueryItem(name: "name", value: name)])
    }

    /// `PUT /api/skills/content`: replaces the SKILL.md of an existing skill. The server checks the frontmatter first.
    public func updateSkillContent(_ name: String, content: String) async throws -> SkillWriteResult {
        try await send("PUT", "/api/skills/content", body: SkillContentBody(name: name, content: content))
    }

    /// `POST /api/skills`: creates a skill from SKILL.md text.
    public func createSkill(_ name: String, content: String, category: String? = nil) async throws -> SkillWriteResult {
        try await send(
            "POST", "/api/skills", body: SkillCreateBody(name: name, content: content, category: category))
    }

    /// `GET /api/skills/hub/official`: the optional-skills catalog, with installed rows marked.
    public func officialSkillCatalog() async throws -> OfficialSkillCatalog {
        try await get("/api/skills/hub/official")
    }

    /// `GET /api/skills/hub/sources`: the hub sources, featured skills and installed identifiers.
    public func skillHubSources() async throws -> SkillHubSources {
        try await get("/api/skills/hub/sources")
    }

    /// `GET /api/skills/hub/search?q=&source=&limit=`. The server searches every source, so this can take a while.
    public func searchSkillHub(_ query: String, source: String = "all", limit: Int = 20) async throws -> SkillHubSearch
    {
        try await get(
            "/api/skills/hub/search",
            query: [
                URLQueryItem(name: "q", value: query), URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "limit", value: String(limit)),
            ])
    }

    /// `GET /api/skills/hub/preview?identifier=`: a hub skill's SKILL.md and files, without installing it.
    public func previewSkillHub(_ identifier: String) async throws -> SkillHubPreview {
        try await get("/api/skills/hub/preview", query: [URLQueryItem(name: "identifier", value: identifier)])
    }

    /// `GET /api/skills/hub/scan?identifier=`: the install-time security scan, run without installing.
    public func scanSkillHub(_ identifier: String) async throws -> SkillHubScan {
        try await get("/api/skills/hub/scan", query: [URLQueryItem(name: "identifier", value: identifier)])
    }

    /// `POST /api/skills/hub/install`: starts the install in the background. Poll the returned action.
    public func installHubSkill(_ identifier: String) async throws -> ServerActionStart {
        try await send("POST", "/api/skills/hub/install", body: SkillIdentifierBody(identifier: identifier))
    }

    /// `POST /api/skills/hub/uninstall`: starts the removal of a hub skill in the background.
    public func uninstallHubSkill(_ name: String) async throws -> ServerActionStart {
        try await send("POST", "/api/skills/hub/uninstall", body: SkillNameBody(name: name))
    }

    /// `POST /api/skills/hub/update`: starts the update of every installed hub skill in the background.
    public func updateHubSkills() async throws -> ServerActionStart {
        try await send("POST", "/api/skills/hub/update")
    }
}
