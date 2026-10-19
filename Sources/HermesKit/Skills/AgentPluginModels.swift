import Foundation

/// One agent plugin from `GET /api/dashboard/plugins/hub`. Agent plugins run on the server, so they work from the phone too.
public struct AgentPlugin: Sendable, Equatable, Codable, Identifiable {
    /// Plugin name.
    public var name: String
    /// Version label from its manifest.
    public var version: String?
    /// One-line description.
    public var description: String?
    /// Where it came from: `bundled`, `user`, `git` or `project`.
    public var source: String?
    /// `enabled`, `disabled` or `inactive`.
    public var runtimeStatus: String?
    /// Directory on the server.
    public var path: String?
    /// True for an install the app may delete. Bundled plugins cannot be removed.
    public var canRemove: Bool?
    /// True for a git install the app may update with a pull.
    public var canUpdateGit: Bool?
    /// True when its tools need a sign-in before they work.
    public var authRequired: Bool?
    /// The command that signs in.
    public var authCommand: String?
    /// Reason from the kill list, when the plugin was removed upstream.
    public var removedReason: String?

    /// Identity for lists.
    public var id: String { name }

    /// True when the plugin is switched on.
    public var isEnabled: Bool { runtimeStatus == "enabled" }
}

/// `GET /api/dashboard/plugins/hub`. Dashboard-only fields (tabs, memory and context providers) are not read here.
public struct AgentPluginHub: Sendable, Equatable, Codable {
    /// Discovered agent plugins.
    public var plugins: [AgentPlugin]
}

/// What a catalog entry lets its plugin do, shown before install.
public struct AgentPluginCapabilities: Sendable, Equatable, Codable {
    /// Tools it registers.
    public var providesTools: [String]?
    /// Hooks it registers.
    public var providesHooks: [String]?
    /// Middleware it adds.
    public var providesMiddleware: [String]?
    /// Environment variables it reads.
    public var requiresEnv: [String]?
}

/// One curated entry of `GET /api/dashboard/plugins/catalog`, merged with what is installed on the server.
public struct AgentPluginCatalogEntry: Sendable, Equatable, Codable, Identifiable {
    /// Catalog name. Install takes it as `catalogName`.
    public var name: String
    /// Human name, when the entry has one.
    public var title: String?
    /// Git repository.
    public var repo: String?
    /// Subdirectory of the repository, for monorepo entries.
    public var subdir: String?
    /// The commit the catalog pins, 40 hex characters.
    public var sha: String?
    /// The first seven characters of the pin.
    public var shaShort: String?
    /// Label for the pinned version, such as `1.4.0`.
    public var version: String?
    /// One-line description.
    public var description: String?
    /// Who maintains it.
    public var maintainer: String?
    /// Review tier, such as `community`.
    public var tier: String?
    /// Category label.
    public var category: String?
    /// Operating systems it supports. Empty means all.
    public var platforms: [String]?
    /// Minimum Hermes version, as text.
    public var requiresHermes: String?
    /// Documentation page.
    public var docsUrl: String?
    /// Tools, hooks, middleware and env vars it declares.
    public var capabilities: AgentPluginCapabilities?
    /// Known problems, as text.
    public var knownIssues: [String]?
    /// True when installed on the server.
    public var installed: Bool?
    /// The commit the installed copy is at.
    public var installedSha: String?
    /// True when the catalog pin moved past the installed commit.
    public var updateAvailable: Bool?
    /// Runtime status when installed.
    public var runtimeStatus: String?

    /// Identity for lists.
    public var id: String { name }
}

/// A catalog entry the kill list withdrew.
public struct AgentPluginRemoved: Sendable, Equatable, Codable {
    /// Catalog or plugin name.
    public var name: String?
    /// Repository it came from.
    public var repo: String?
    /// Why it was withdrawn.
    public var reason: String?
    /// When it was withdrawn.
    public var date: String?
}

/// `GET /api/dashboard/plugins/catalog`.
public struct AgentPluginCatalog: Sendable, Equatable, Codable {
    /// Curated entries.
    public var entries: [AgentPluginCatalogEntry]
    /// Withdrawn entries.
    public var removed: [AgentPluginRemoved]?
    /// When the server built the list, in ISO 8601.
    public var generatedAt: String?
}

/// What `POST /api/dashboard/agent-plugins/install` installs: a git URL, or a catalog entry by name. The server
/// requires `identifier` even when `catalogName` is set, so it is sent as an empty string then.
public struct AgentPluginInstallRequest: Sendable, Equatable, Encodable {
    /// Git URL, optionally `url#subdir`. Empty for a catalog install.
    public var identifier: String
    /// Catalog entry to install, by its catalog name.
    public var catalogName: String?
    /// Commit to pin the install to: 40 hex characters. Nil installs the default branch.
    public var ref: String?
    /// Replaces an existing install of the same plugin.
    public var force: Bool
    /// Switches the plugin on after install.
    public var enable: Bool

    /// Creates a request. Use `catalogName` for a catalog install, or `identifier` for a git install.
    public init(
        identifier: String = "", catalogName: String? = nil, ref: String? = nil, force: Bool = false,
        enable: Bool = true
    ) {
        self.identifier = identifier
        self.catalogName = catalogName
        self.ref = ref
        self.force = force
        self.enable = enable
    }

    /// True when `text` is a full commit id (40 hex characters), the only form `ref` takes. Short ids are refused.
    public static func isCommitSHA(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }
}

/// The answer of an agent plugin change: install, enable, disable, update, remove or activate.
///
/// When `consentRequired` is true nothing changed. The update would widen what the plugin may do: show `deltaLines`,
/// then retry with `acceptCapabilities`.
public struct AgentPluginResult: Sendable, Equatable, Codable {
    /// True when the change succeeded.
    public var ok: Bool?
    /// Plugin name.
    public var name: String?
    /// Plugin name as installed, for installs.
    public var pluginName: String?
    /// True when nothing had to change.
    public var unchanged: Bool?
    /// True when a running gateway must restart before the change takes effect.
    public var restartRequired: Bool?
    /// True when the plugin is switched on after the change.
    public var enabled: Bool?
    /// The commit the plugin is at after install or update.
    public var sha: String?
    /// Notes from the install.
    public var warnings: [String]?
    /// Environment variables the plugin needs that are not set.
    public var missingEnv: [String]?
    /// Known problems of the catalog entry.
    public var knownIssues: [String]?
    /// True when an update must be confirmed first.
    public var consentRequired: Bool?
    /// What the update adds, one line each.
    public var deltaLines: [String]?
    /// Output of a git pull, for updates of a git install.
    public var output: String?
    /// Why the change was refused, when the server says so in the body.
    public var error: String?
}

/// `GET /api/dashboard/plugins/rescan`.
public struct AgentPluginRescan: Sendable, Equatable, Codable {
    /// True when the folders were read.
    public var ok: Bool?
    /// Plugins found.
    public var count: Int?
}
