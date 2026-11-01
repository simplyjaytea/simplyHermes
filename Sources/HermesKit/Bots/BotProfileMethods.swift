import Foundation

/// `profiles.configure`: applies any subset of a profile's sections. Sections are independent (contract
/// `ProfilesConfigureParams`). Bot-only sections are here so the Bots feature owns them; the Settings feature
/// owns the rest.
public struct ProfilesConfigureParams: Sendable, Equatable, Codable {
    public var profile: String?
    public var name: String?
    /// Namespaces to write, each replaced whole (`{"hermes-bots": {...}, "simplyhermes": {...}}`).
    public var uiMeta: JSONValue?
    /// Per-namespace revisions the server must still report. A mismatch rejects the whole `ui_meta` write.
    public var uiMetaExpectedRevisions: [String: Int]?
    public var soul: String?
    public var description: String?
    public var model: String?
    public var provider: String?
    /// Set to `true` to resend a model change that returned `confirm_required`.
    public var confirmExpensiveModel: Bool?
    public var disabledSkills: [String]?
    public var enabledToolsets: [String]?
    public var enabledMCPServers: [String]?

    public init(
        profile: String? = nil, name: String? = nil, uiMeta: JSONValue? = nil,
        uiMetaExpectedRevisions: [String: Int]? = nil, soul: String? = nil, description: String? = nil,
        model: String? = nil, provider: String? = nil, confirmExpensiveModel: Bool? = nil,
        disabledSkills: [String]? = nil, enabledToolsets: [String]? = nil, enabledMCPServers: [String]? = nil
    ) {
        self.profile = profile
        self.name = name
        self.uiMeta = uiMeta
        self.uiMetaExpectedRevisions = uiMetaExpectedRevisions
        self.soul = soul
        self.description = description
        self.model = model
        self.provider = provider
        self.confirmExpensiveModel = confirmExpensiveModel
        self.disabledSkills = disabledSkills
        self.enabledToolsets = enabledToolsets
        self.enabledMCPServers = enabledMCPServers
    }

    enum CodingKeys: String, CodingKey {
        case profile, name, soul, description, model, provider
        case uiMeta = "ui_meta"
        case uiMetaExpectedRevisions = "ui_meta_expected_revisions"
        case confirmExpensiveModel = "confirm_expensive_model"
        case disabledSkills = "disabled_skills"
        case enabledToolsets = "enabled_toolsets"
        case enabledMCPServers = "enabled_mcp_servers"
    }
}

/// The per-section outcome of `profiles.configure`. Only the sections the request carried are present.
public struct ProfilesConfigureApplied: Sendable, Equatable, Codable {
    public var uiMeta: Bool?
    public var uiMetaRevisions: [String: Int]?
    public var uiMetaConflicts: [String: UiMetaConflict]?
    public var soul: Bool?
    public var description: Bool?
    public var model: Bool?
    public var skills: Bool?
    public var toolsets: Bool?
    public var mcpServers: Bool?

    enum CodingKeys: String, CodingKey {
        case soul, description, model, skills, toolsets
        case uiMeta = "ui_meta"
        case uiMetaRevisions = "ui_meta_revisions"
        case uiMetaConflicts = "ui_meta_conflicts"
        case mcpServers = "mcp_servers"
    }
}

/// A compare-and-swap mismatch for one namespace: the revision the client expected and the one stored.
public struct UiMetaConflict: Sendable, Equatable, Codable {
    public var expected: Int?
    public var actual: Int
}

public struct ProfilesConfigureResult: Sendable, Equatable, Codable {
    public var ok: Bool
    public var applied: ProfilesConfigureApplied
    /// True when a guarded model change wrote nothing and needs `confirm_expensive_model`.
    public var confirmRequired: Bool?
    public var confirmMessage: String?

    enum CodingKeys: String, CodingKey {
        case ok, applied
        case confirmRequired = "confirm_required"
        case confirmMessage = "confirm_message"
    }
}
