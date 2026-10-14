import Foundation

/// `GET /api/health`.
public struct ServerHealth: Sendable, Equatable, Codable {
    /// True when the server is up.
    public var ok: Bool
    /// Package version. `"unknown"` on git installs.
    public var version: String?
    /// Version for display, such as `git.d97007c`.
    public var displayVersion: String?
    /// Git commit, when known.
    public var commit: String?
    /// True when requests need a login.
    public var authRequired: Bool?
}

/// `GET /api/host/identity`: tells a dashboard apart from other servers on the same port.
public struct HostIdentity: Sendable, Equatable, Codable {
    /// True for a Hermes dashboard.
    public var ok: Bool
    /// Host protocol version.
    public var protocolVersion: Int?
    /// Server process id.
    public var pid: Int?
    /// `serve` for `hermes serve`.
    public var role: String?
    /// True when the server also serves the web app.
    public var servesSpa: Bool?
}

/// `GET /api/status`: version, gateway and health. Only the fields the app reads are modelled.
public struct ServerStatus: Sendable, Equatable, Codable {
    /// Package version.
    public var version: String?
    /// Release date such as `2026.9.24`. Use it, with `configVersion`, for compatibility checks.
    public var releaseDate: String?
    /// Config schema version of this install.
    public var configVersion: Int?
    /// Newest config schema version the code knows.
    public var latestConfigVersion: Int?
    /// True when a messaging gateway is running.
    public var gatewayRunning: Bool?
    /// Agents running now.
    public var activeAgents: Int?
    /// Sessions open now.
    public var activeSessions: Int?
    /// True when requests need a login.
    public var authRequired: Bool?
    /// Login providers such as `basic`.
    public var authProviders: [String]?
    /// `ok`, `degraded` or `down`.
    public var overall: String?
    /// Profile names.
    public var profiles: [String]?
}

/// `GET /api/auth/me`.
public struct AuthUser: Sendable, Equatable, Codable {
    /// User id.
    public var userId: String
    /// Email, possibly empty.
    public var email: String?
    /// Name to show.
    public var displayName: String?
    /// Login provider such as `basic`.
    public var provider: String?
    /// Unix time when the login expires.
    public var expiresAt: Int?
}

/// One profile from `GET /api/profiles`.
public struct HermesProfile: Sendable, Equatable, Codable, Identifiable {
    /// Profile name, unique.
    public var name: String
    /// Home directory on the server.
    public var path: String?
    /// True for the default profile.
    public var isDefault: Bool?
    /// Model in use.
    public var model: String?
    /// Provider in use.
    public var provider: String?
    /// Installed skills.
    public var skillCount: Int?
    /// True when this profile's gateway runs.
    public var gatewayRunning: Bool?
    /// Description, possibly empty.
    public var description: String?
    /// Name to show, possibly empty.
    public var displayName: String?
    /// Identity for lists.
    public var id: String { name }
}

/// `GET /api/profiles`.
public struct ProfileList: Sendable, Equatable, Codable {
    /// All profiles.
    public var profiles: [HermesProfile]
}

/// `GET /api/profiles/active`.
public struct ActiveProfile: Sendable, Equatable, Codable {
    /// The profile stored as active.
    public var active: String
    /// The profile this process runs under.
    public var current: String?
}

/// `GET /api/model/info`.
public struct ModelInfo: Sendable, Equatable, Codable {
    /// Model id.
    public var model: String
    /// Provider slug.
    public var provider: String?
    /// Context window the server works with.
    public var effectiveContextLength: Int?
}

/// One provider in `GET /api/model/options`.
public struct ModelProviderOptions: Sendable, Equatable, Codable, Identifiable {
    /// Provider slug.
    public var slug: String
    /// Name to show.
    public var name: String
    /// True for the provider in use.
    public var isCurrent: Bool?
    /// Model ids to offer.
    public var models: [String]?
    /// Total models, which can exceed `models`.
    public var totalModels: Int?
    /// True when credentials are set.
    public var authenticated: Bool?
    /// Identity for lists.
    public var id: String { slug }
}

/// `GET /api/model/options`.
public struct ModelOptions: Sendable, Equatable, Codable {
    /// Providers and their models.
    public var providers: [ModelProviderOptions]
    /// Current model.
    public var model: String?
    /// Current provider.
    public var provider: String?
}

/// One skill from `GET /api/skills`.
public struct SkillInfo: Sendable, Equatable, Codable, Identifiable {
    /// Skill name.
    public var name: String
    /// One-line description.
    public var description: String?
    /// Category such as `autonomous-ai-agents`.
    public var category: String?
    /// True when on.
    public var enabled: Bool
    /// Uses so far.
    public var usage: Int?
    /// `bundled`, `hub` or `local`.
    public var provenance: String?
    /// Identity for lists.
    public var id: String { name }
}

/// One toolset from `GET /api/tools/toolsets`.
public struct ToolsetInfo: Sendable, Equatable, Codable, Identifiable {
    /// Toolset name.
    public var name: String
    /// Name to show.
    public var label: String?
    /// Description.
    public var description: String?
    /// True when on.
    public var enabled: Bool
    /// True when its requirements are met.
    public var available: Bool?
    /// True when it is set up.
    public var configured: Bool?
    /// Tool names inside.
    public var tools: [String]?
    /// Identity for lists.
    public var id: String { name }
}
