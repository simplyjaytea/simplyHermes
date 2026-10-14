/// Params for methods that take none. Encodes as `{}`.
public struct EmptyParams: Sendable, Equatable, Codable {
    /// Creates empty params.
    public init() {}
}

/// Params of `client.capabilities`. Send it right after `gateway.ready`; without it, approvals are withdrawn.
public struct ClientCapabilitiesParams: Sendable, Equatable, Codable {
    /// True to receive server-to-client requests such as `approval`.
    public var serverRequests: Bool

    /// Creates the params.
    public init(serverRequests: Bool) {
        self.serverRequests = serverRequests
    }

    enum CodingKeys: String, CodingKey {
        case serverRequests = "server_requests"
    }
}

/// Result of `client.capabilities`.
public struct ClientCapabilitiesResult: Sendable, Equatable, Codable {
    /// Server requests this server will send to the client.
    public var serverRequests: [String]
    /// True when declined requests are not shown to the user.
    public var declinesNotShown: Bool?

    enum CodingKeys: String, CodingKey {
        case serverRequests = "server_requests"
        case declinesNotShown = "declines_not_shown"
    }
}

/// Result of `gateway.capabilities`.
public struct GatewayCapabilitiesResult: Sendable, Equatable, Codable {
    /// True when a session accepts one submit at a time.
    public var perSessionExclusiveSubmit: Bool

    enum CodingKeys: String, CodingKey {
        case perSessionExclusiveSubmit = "per_session_exclusive_submit"
    }
}

/// Result of `ping`.
public struct PingResult: Sendable, Equatable, Codable {
    /// Always true.
    public var pong: Bool
}

/// Result of `gateway.ping`, the heartbeat.
public struct GatewayPingResult: Sendable, Equatable, Codable {
    /// Always true.
    public var ok: Bool
}

/// Params of `model.options`.
public struct ModelOptionsParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Session the request is scoped to.
    public var sessionID: String?
    /// Only list models named in the configuration.
    public var explicitOnly: Bool?
    /// Include providers with no credentials.
    public var includeUnconfigured: Bool?
    /// Refresh the provider catalogs.
    public var refresh: Bool?

    /// Creates the params.
    public init(
        profile: String? = nil, sessionID: String? = nil, explicitOnly: Bool? = nil,
        includeUnconfigured: Bool? = nil, refresh: Bool? = nil
    ) {
        self.profile = profile
        self.sessionID = sessionID
        self.explicitOnly = explicitOnly
        self.includeUnconfigured = includeUnconfigured
        self.refresh = refresh
    }

    enum CodingKeys: String, CodingKey {
        case profile, refresh
        case sessionID = "session_id"
        case explicitOnly = "explicit_only"
        case includeUnconfigured = "include_unconfigured"
    }
}

/// One provider in `model.options`. Capability, pricing and limit tables stay raw.
public struct ModelOptionProvider: Sendable, Equatable, Codable {
    /// Provider id.
    public var slug: String
    /// Display name.
    public var name: String
    /// Model names.
    public var models: [String]?
    /// Total number of models, when the list is truncated.
    public var totalModels: Int?
    /// True for the provider the session uses.
    public var isCurrent: Bool?
    /// True when the user defined this provider.
    public var isUserDefined: Bool?
    /// Where the provider was read from.
    public var source: String?
    /// Other names that resolve to this provider.
    public var aliases: [String]?
    /// Base URL of the provider API.
    public var apiURL: String?
    /// Authentication type.
    public var authType: String?
    /// True when credentials are configured.
    public var authenticated: Bool?
    /// Environment variable that holds the key.
    public var keyEnv: String?
    /// Warning text, when the provider needs attention.
    public var warning: String?
    /// Models to show first.
    public var featuredModels: [String]?
    /// Per-model capability flags. Kept raw.
    public var capabilities: JSONValue?
    /// Per-model pricing. Kept raw.
    public var pricing: JSONValue?
    /// True while pricing is loading.
    public var pricingPending: Bool?
    /// True when the provider has a free tier.
    public var freeTier: Bool?
    /// True while the free-tier status is loading.
    public var freeTierPending: Bool?
    /// True when the free-tier status is a row in the list.
    public var freeTierRow: Bool?
    /// Models that cannot be used. Kept as names.
    public var unavailableModels: [String]?
    /// Rate limits. Kept raw.
    public var limit: JSONValue?
    /// Usage against the provider. Kept raw.
    public var usage: JSONValue?

    enum CodingKeys: String, CodingKey {
        case slug, name, models, source, aliases, warning, capabilities, pricing, limit, usage, authenticated
        case totalModels = "total_models"
        case isCurrent = "is_current"
        case isUserDefined = "is_user_defined"
        case apiURL = "api_url"
        case authType = "auth_type"
        case keyEnv = "key_env"
        case featuredModels = "featured_models"
        case pricingPending = "pricing_pending"
        case freeTier = "free_tier"
        case freeTierPending = "free_tier_pending"
        case freeTierRow = "free_tier_row"
        case unavailableModels = "unavailable_models"
    }
}

/// Result of `model.options`.
public struct ModelOptionsResult: Sendable, Equatable, Codable {
    /// Providers and their models.
    public var providers: [ModelOptionProvider]
    /// Current model.
    public var model: String?
    /// Current provider.
    public var provider: String?
}

/// Params of `config.get`.
public struct ConfigGetParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Config key, such as `display`.
    public var key: String
    /// Working directory to read config for.
    public var cwd: String?
    /// Session the request is scoped to.
    public var sessionID: String?

    /// Creates a config query.
    public init(key: String, profile: String? = nil, cwd: String? = nil, sessionID: String? = nil) {
        self.key = key
        self.profile = profile
        self.cwd = cwd
        self.sessionID = sessionID
    }

    enum CodingKeys: String, CodingKey {
        case profile, key, cwd
        case sessionID = "session_id"
    }
}

/// Result of `config.get`. The server answers `4002` for an unknown key.
public struct ConfigGetResult: Sendable, Equatable, Codable {
    /// The value. Its type depends on the key.
    public var value: JSONValue?
    /// Display setting, when the key is `display`.
    public var display: String?
    /// Tool progress setting.
    public var toolProgress: String?
    /// Current model.
    public var model: String?
    /// Current provider.
    public var provider: String?
    /// Providers. Kept raw.
    public var providers: JSONValue?
    /// Home directory on the server.
    public var home: String?
    /// Working directory on the server.
    public var cwd: String?
    /// Git branch.
    public var branch: String?
    /// The whole config, when requested. Kept raw.
    public var config: JSONValue?
    /// Prompt text, when the key is a prompt.
    public var prompt: String?
    /// When the config file last changed (Unix seconds).
    public var mtime: Double?
    /// Revision of the MCP configuration.
    public var mcpRev: String?

    enum CodingKeys: String, CodingKey {
        case value, display, model, provider, providers, home, cwd, branch, config, prompt, mtime
        case toolProgress = "tool_progress"
        case mcpRev = "mcp_rev"
    }
}

/// Params of `commands.catalog`.
public struct CommandsCatalogParams: Sendable, Equatable, Codable {
    /// Session the catalog is for.
    public var sessionID: String?
    /// Profile the catalog is for.
    public var profile: String?

    /// Creates the params.
    public init(sessionID: String? = nil, profile: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
    }
}

/// A group of slash commands in `commands.catalog`.
public struct CommandCategory: Sendable, Equatable, Codable {
    /// Category name.
    public var name: String
    /// `[name, description]` pairs.
    public var pairs: [[String]]
}

/// Result of `commands.catalog`. `pairs` is `[[name, description]]`.
public struct CommandsCatalogResult: Sendable, Equatable, Codable {
    /// All slash commands as `[name, description]` pairs.
    public var pairs: [[String]]?
    /// Subcommands by command name.
    public var sub: [String: [String]]?
    /// Alias to canonical name.
    public var canon: [String: String]?
    /// Command metadata by name. Kept raw.
    public var commands: JSONValue?
    /// Commands grouped by category.
    public var categories: [CommandCategory]?
    /// Installed skills. Kept raw.
    public var skills: JSONValue?
    /// Number of skills.
    public var skillCount: Int?
    /// Warning text, when the catalog is partial.
    public var warning: String?

    enum CodingKeys: String, CodingKey {
        case pairs, sub, canon, commands, categories, skills, warning
        case skillCount = "skill_count"
    }
}

/// Params of `subagent.list` are ``SubagentListParams`` (a session id). This is its result.
public struct SubagentListResult: Sendable, Equatable, Codable {
    /// Live child agents.
    public var subagents: [SubagentSnapshot]
    /// Delegations that failed to start or finish.
    public var delegations: [FailedDelegation]
}

/// One live child agent in `subagent.list`.
public struct SubagentSnapshot: Sendable, Equatable, Codable {
    /// Id of the child.
    public var subagentID: String
    /// Id of the parent agent.
    public var parentID: String?
    /// Nesting depth.
    public var depth: Int?
    /// What the child was asked to do.
    public var goal: String?
    /// Id of the delegation.
    public var delegationID: String?
    /// Model the child uses.
    public var model: String?
    /// When the child started (Unix seconds).
    public var startedAt: Double?
    /// Lifecycle status.
    public var status: SubagentStatus?
    /// Tools the child has used.
    public var toolCount: Int?
    /// Name of the last tool it used.
    public var lastTool: String?
    /// True when the child accepts a steering message.
    public var acceptingSteer: Bool?

    enum CodingKeys: String, CodingKey {
        case depth, goal, model, status
        case subagentID = "subagent_id"
        case parentID = "parent_id"
        case delegationID = "delegation_id"
        case startedAt = "started_at"
        case toolCount = "tool_count"
        case lastTool = "last_tool"
        case acceptingSteer = "accepting_steer"
    }
}

/// A delegation that failed, in `subagent.list`.
public struct FailedDelegation: Sendable, Equatable, Codable {
    /// Id of the delegation.
    public var delegationID: String
    /// Index of the task within the delegation.
    public var taskIndex: Int?
    /// Status text.
    public var status: String
    /// What the task was asked to do.
    public var goal: String?
    /// Error text.
    public var error: String?
    /// When it was dispatched (Unix seconds).
    public var dispatchedAt: Double?
    /// When it completed (Unix seconds).
    public var completedAt: Double?

    enum CodingKeys: String, CodingKey {
        case status, goal, error
        case delegationID = "delegation_id"
        case taskIndex = "task_index"
        case dispatchedAt = "dispatched_at"
        case completedAt = "completed_at"
    }
}

/// Params of `spawn_tree.list`.
public struct SpawnTreeListParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Session whose tree to list.
    public var sessionID: String?
    /// Include trees across sessions.
    public var crossSession: Bool?
    /// Maximum entries.
    public var limit: Int?

    /// Creates the params.
    public init(profile: String? = nil, sessionID: String? = nil, crossSession: Bool? = nil, limit: Int? = nil) {
        self.profile = profile
        self.sessionID = sessionID
        self.crossSession = crossSession
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case profile, limit
        case sessionID = "session_id"
        case crossSession = "cross_session"
    }
}

/// Result of `spawn_tree.list`.
public struct SpawnTreeListResult: Sendable, Equatable, Codable {
    /// Spawned runs, one per path.
    public var entries: [SpawnTreeEntry]
}

/// One run in the spawn tree.
public struct SpawnTreeEntry: Sendable, Equatable, Codable {
    /// Path of the run in the tree.
    public var path: String
    /// Session the run belongs to.
    public var sessionID: String?
    /// When the run started (Unix seconds).
    public var startedAt: Double?
    /// When the run finished (Unix seconds).
    public var finishedAt: Double?
    /// Display label.
    public var label: String?
    /// Number of runs under this path.
    public var count: Int?

    enum CodingKeys: String, CodingKey {
        case path, label, count
        case sessionID = "session_id"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}
