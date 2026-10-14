/// Params of `profiles.list`.
public struct ProfilesListParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Include recent session previews in each row.
    public var includeSessions: Bool?

    /// Creates list params.
    public init(profile: String? = nil, includeSessions: Bool? = nil) {
        self.profile = profile
        self.includeSessions = includeSessions
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case includeSessions = "include_sessions"
    }
}

/// Result of `profiles.list`. A profile is a bot when it is not the default.
public struct ProfilesListResult: Sendable, Equatable, Codable {
    /// Profiles on this server.
    public var profiles: [ProfileRow]
    /// True when this backend injects the teammate-messaging protocol.
    public var botModeProtocol: Bool
    /// Stable id of this server installation.
    public var installID: String

    enum CodingKeys: String, CodingKey {
        case profiles
        case botModeProtocol = "bot_mode_protocol"
        case installID = "install_id"
    }
}

/// One profile in `profiles.list`. Session previews and UI metadata stay raw.
public struct ProfileRow: Sendable, Equatable, Codable {
    /// Profile name.
    public var name: String
    /// Path of the profile on the server.
    public var path: String
    /// True for the default profile.
    public var isDefault: Bool?
    /// Model pinned for the profile.
    public var model: String?
    /// Provider of the model.
    public var provider: String?
    /// Description the user wrote.
    public var description: String?
    /// Display name.
    public var displayName: String?
    /// Number of skills.
    public var skillCount: Int?
    /// Names the profile used before a rename.
    public var previousNames: [String]?
    /// Most recent session, when `include_sessions` was set. Kept raw.
    public var lastSession: JSONValue?
    /// Worker session of a bot. Kept raw.
    public var workerSession: JSONValue?
    /// Canonical session of a bot. Kept raw.
    public var canonicalSession: JSONValue?
    /// Revision counters for the UI metadata.
    public var uiMetaRevisions: [String: Int]?
    /// UI metadata (look, title, sections). Kept raw; it carries compare-and-swap revisions.
    public var uiMeta: JSONValue?
    /// True when the profile has an avatar.
    public var hasAvatar: Bool?

    enum CodingKeys: String, CodingKey {
        case name, path, model, provider, description
        case isDefault = "is_default"
        case displayName = "display_name"
        case skillCount = "skill_count"
        case previousNames = "previous_names"
        case lastSession = "last_session"
        case workerSession = "worker_session"
        case canonicalSession = "canonical_session"
        case uiMetaRevisions = "ui_meta_revisions"
        case uiMeta = "ui_meta"
        case hasAvatar = "has_avatar"
    }
}

/// Params of `profiles.create`.
public struct ProfilesCreateParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Name of the new profile.
    public var name: String
    /// Description of the new profile.
    public var description: String?
    /// Profile to clone the configuration from.
    public var cloneFrom: String?
    /// Clone everything, not only the configuration.
    public var cloneAll: Bool?
    /// Clone channel settings.
    public var cloneChannels: Bool?
    /// Do not copy skills.
    public var noSkills: Bool?
    /// Do not create a command alias.
    public var noAlias: Bool?
    /// Personality text (SOUL) for the new profile.
    public var soul: String?
    /// Model to pin.
    public var model: String?
    /// Provider to pin.
    public var provider: String?
    /// Share auth with the source profile.
    public var shareAuth: Bool?
    /// Mirror credentials from the source profile.
    public var mirrorCredentials: Bool?

    /// Creates a profile.
    public init(
        name: String, profile: String? = nil, description: String? = nil, cloneFrom: String? = nil,
        cloneAll: Bool? = nil, cloneChannels: Bool? = nil, noSkills: Bool? = nil, noAlias: Bool? = nil,
        soul: String? = nil, model: String? = nil, provider: String? = nil, shareAuth: Bool? = nil,
        mirrorCredentials: Bool? = nil
    ) {
        self.name = name
        self.profile = profile
        self.description = description
        self.cloneFrom = cloneFrom
        self.cloneAll = cloneAll
        self.cloneChannels = cloneChannels
        self.noSkills = noSkills
        self.noAlias = noAlias
        self.soul = soul
        self.model = model
        self.provider = provider
        self.shareAuth = shareAuth
        self.mirrorCredentials = mirrorCredentials
    }

    enum CodingKeys: String, CodingKey {
        case profile, name, description, soul, model, provider
        case cloneFrom = "clone_from"
        case cloneAll = "clone_all"
        case cloneChannels = "clone_channels"
        case noSkills = "no_skills"
        case noAlias = "no_alias"
        case shareAuth = "share_auth"
        case mirrorCredentials = "mirror_credentials"
    }
}

/// Result of `profiles.create`. A name clash returns `4062`.
public struct ProfilesCreateResult: Sendable, Equatable, Codable {
    /// True when the profile was created.
    public var ok: Bool?
    /// Name of the new profile.
    public var name: String
    /// Path of the new profile on the server.
    public var path: String
    /// True when the SOUL text was written.
    public var soulWritten: Bool?
    /// True when the model was pinned.
    public var modelSet: Bool?
    /// What was mirrored from the source profile. Kept raw.
    public var mirrored: JSONValue?

    enum CodingKeys: String, CodingKey {
        case ok, name, path, mirrored
        case soulWritten = "soul_written"
        case modelSet = "model_set"
    }
}

/// Params of `profiles.describe`.
public struct ProfilesDescribeParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Profile to describe.
    public var name: String?

    /// Creates describe params.
    public init(profile: String? = nil, name: String? = nil) {
        self.profile = profile
        self.name = name
    }
}

/// Result of `profiles.describe`.
public struct ProfilesDescribeResult: Sendable, Equatable, Codable {
    /// Profile name.
    public var name: String
    /// Description.
    public var description: String?
    /// Personality text (SOUL).
    public var soul: String?
    /// Pinned provider and model.
    public var model: ProfileModelPin
    /// Skills and whether each is enabled.
    public var skills: [CapabilityEntry]?
    /// Toolsets and whether each is enabled.
    public var toolsets: [ToolsetEntry]?
    /// True when the toolsets are pinned rather than inherited.
    public var toolsetsPinned: Bool?
    /// MCP servers and whether each is enabled.
    public var mcpServers: [McpServerEntry]?

    enum CodingKeys: String, CodingKey {
        case name, description, soul, model, skills, toolsets
        case toolsetsPinned = "toolsets_pinned"
        case mcpServers = "mcp_servers"
    }
}

/// The provider and model a profile is pinned to.
public struct ProfileModelPin: Sendable, Equatable, Codable {
    /// Provider name.
    public var provider: String
    /// Default model name.
    public var defaultModel: String

    enum CodingKeys: String, CodingKey {
        case provider
        case defaultModel = "default"
    }
}

/// A named skill or capability and whether it is enabled.
public struct CapabilityEntry: Sendable, Equatable, Codable {
    /// Name of the skill or capability.
    public var name: String
    /// Whether it is enabled.
    public var enabled: Bool?
}

/// A toolset and its state.
public struct ToolsetEntry: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String
    /// Whether it is enabled.
    public var enabled: Bool?
    /// Display label.
    public var label: String?
    /// Description.
    public var description: String?
    /// Number of tools in the set.
    public var toolCount: Int?

    enum CodingKeys: String, CodingKey {
        case name, enabled, label, description
        case toolCount = "tool_count"
    }
}

/// An MCP server and its state.
public struct McpServerEntry: Sendable, Equatable, Codable {
    /// Server name.
    public var name: String
    /// Whether it is enabled.
    public var enabled: Bool?
    /// Transport kind, for example `stdio`.
    public var transport: String?
}
