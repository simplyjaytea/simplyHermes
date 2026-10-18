import Foundation

/// One MCP server from `GET /api/mcp/servers`.
///
/// The server masks secret values: `env` maps each variable name to a redacted value. The app shows variable names
/// only and never sends these values back.
public struct MCPServerInfo: Sendable, Equatable, Codable, Identifiable {
    /// Server name. Unique in the profile.
    public var name: String
    /// `stdio` for a command, `http` for a URL, or `unknown`.
    public var transport: String?
    /// Address of an `http` server.
    public var url: String?
    /// Program a `stdio` server starts.
    public var command: String?
    /// Arguments for ``command``.
    public var args: [String]?
    /// Variable name to redacted value.
    public var env: [String: String]?
    /// `none`, `header` (bearer token) or `oauth`, when set.
    public var auth: String?
    /// True when the server is switched on.
    public var enabled: Bool
    /// `config` for a server in config.yaml, `plugin` for a server a plugin provides.
    public var source: String?
    /// The plugin that provides the server, if any.
    public var plugin: String?

    /// Identity for lists.
    public var id: String { name }

    /// Plugin servers are read-only here: the server refuses changes to them.
    public var isEditable: Bool { source != "plugin" }

    /// True for an HTTP server that can sign in with OAuth. A server that sends a header token cannot.
    public var supportsOAuth: Bool { !(url ?? "").isEmpty && auth != "header" }

    /// Names of the variables the server starts with, sorted. Values are never shown.
    public var envNames: [String] { (env ?? [:]).keys.sorted() }
}

/// `GET /api/mcp/servers`: every server in the profile, sorted by name.
public struct MCPServerList: Sendable, Equatable, Codable {
    /// The servers.
    public var servers: [MCPServerInfo]
}

/// Body of `POST /api/mcp/servers`. Set exactly one of ``url`` (HTTP) or ``command`` (stdio).
///
/// ``auth`` is `none` when nil, `header` (needs ``bearerToken``) or `oauth`. The server keeps the bearer token in
/// its own secret store and never returns it.
public struct MCPServerCreate: Sendable, Equatable, Codable {
    /// Server name.
    public var name: String
    /// Address of an HTTP server.
    public var url: String?
    /// Program of a stdio server.
    public var command: String?
    /// Arguments of a stdio server.
    public var args: [String]
    /// Variables of a stdio server. Values can be secrets.
    public var env: [String: String]
    /// `header` or `oauth` for an HTTP server. Nil means no authentication.
    public var auth: String?
    /// Bearer token, sent with `auth` `header`.
    public var bearerToken: String?

    /// Creates a request body.
    public init(
        name: String, url: String? = nil, command: String? = nil, args: [String] = [], env: [String: String] = [:],
        auth: String? = nil, bearerToken: String? = nil
    ) {
        self.name = name
        self.url = url
        self.command = command
        self.args = args
        self.env = env
        self.auth = auth
        self.bearerToken = bearerToken
    }
}

/// Body of `PUT /api/mcp/servers`: the whole `mcp_servers` map. The server replaces every entry with these.
public struct MCPServersReplace: Sendable, Equatable, Codable {
    /// Every server, keyed by name. Send the complete map, never a part of it.
    public var servers: [String: JSONValue]

    /// Creates a body.
    public init(servers: [String: JSONValue]) {
        self.servers = servers
    }
}

/// `POST /api/mcp/servers/{name}/test`. A failed probe answers `ok: false` with an ``error`` and no tools.
public struct MCPServerTestResult: Sendable, Equatable, Codable {
    /// True when the server connected and listed its tools.
    public var ok: Bool
    /// Why the probe failed.
    public var error: String?
    /// Tools the server exposes.
    public var tools: [MCPToolInfo]?
    /// Number of prompts, on success.
    public var prompts: Int?
    /// Number of resources, on success.
    public var resources: Int?
}

/// One tool an MCP server exposes.
public struct MCPToolInfo: Sendable, Equatable, Codable, Identifiable {
    /// Tool name.
    public var name: String
    /// What the tool does.
    public var description: String?
    /// Size of the tool's schema in characters, when the server reports it.
    public var schemaChars: Int?

    /// Identity for lists.
    public var id: String { name }
}

/// An MCP OAuth sign-in. It is the answer to `POST /api/mcp/servers/{name}/auth` and to
/// `GET /api/mcp/oauth/flows/{flow_id}`.
public struct MCPOAuthFlow: Sendable, Equatable, Codable {
    /// Id to poll and cancel the flow with.
    public var flowId: String
    /// The server being signed in.
    public var serverName: String?
    /// `starting`, `authorization_required`, `approved` or `error`.
    public var status: String
    /// The page the user opens to sign in. Set once the server has one.
    public var authorizationUrl: String?
    /// Why the flow failed, when ``status`` is `error`.
    public var error: String?
    /// Tools found after a successful sign-in.
    public var tools: [MCPToolInfo]?

    /// True once the flow ended, approved or failed. Polling stops here.
    public var isFinished: Bool { status == "approved" || status == "error" }

    /// True when the sign-in finished and the server is connected.
    public var isApproved: Bool { status == "approved" }
}

/// `GET /api/mcp/catalog`: the approved catalog, each entry with its install state.
public struct MCPCatalog: Sendable, Equatable, Codable {
    /// Catalog entries.
    public var entries: [MCPCatalogEntry]
    /// Entries the server could not load, with the reason.
    public var diagnostics: [MCPCatalogDiagnostic]?
}

/// One catalog entry. Read the transport details before installing: they say what the server runs.
public struct MCPCatalogEntry: Sendable, Equatable, Codable, Identifiable {
    /// Entry name. Used to install it.
    public var name: String
    /// What the server does.
    public var description: String?
    /// Kind of connector the entry belongs to, if any.
    public var connectorSlug: String?
    /// Where the entry comes from.
    public var source: String?
    /// Transport kind, such as `stdio` or `http`.
    public var transport: String?
    /// Authentication kind, such as `none`, `header` or `oauth`.
    public var authType: String?
    /// Variables the user supplies. Names and prompts only.
    public var requiredEnv: [MCPCatalogEnvVar]?
    /// Program the server runs (stdio).
    public var command: String?
    /// Arguments of ``command``.
    public var args: [String]?
    /// Address the server uses (HTTP).
    public var url: String?
    /// Git repository cloned and built on the server before the install, if any.
    public var installUrl: String?
    /// Git ref of ``installUrl``.
    public var installRef: String?
    /// Text the server shows after the install.
    public var postInstall: String?
    /// True when a git clone and build runs first.
    public var needsInstall: Bool?
    /// True when the entry is already in config.
    public var installed: Bool?
    /// True when the installed entry is switched on.
    public var enabled: Bool?

    /// Identity for lists.
    public var id: String { name }
}

/// A variable a catalog entry needs. The value is entered once and never read back.
public struct MCPCatalogEnvVar: Sendable, Equatable, Codable {
    /// Variable name.
    public var name: String
    /// Label the server suggests for the value.
    public var prompt: String?
    /// True when the entry cannot work without it.
    public var required: Bool?
}

/// A catalog entry the server could not load.
public struct MCPCatalogDiagnostic: Sendable, Equatable, Codable {
    /// Entry name, when known.
    public var name: String?
    /// Kind of problem.
    public var kind: String?
    /// What went wrong.
    public var message: String?
}

/// Body of `POST /api/mcp/catalog/install`. ``env`` holds only the variables the entry declares.
public struct MCPCatalogInstall: Sendable, Equatable, Codable {
    /// Entry name.
    public var name: String
    /// Values for the entry's variables.
    public var env: [String: String]
    /// True to switch the server on after the install.
    public var enable: Bool

    /// Creates a body.
    public init(name: String, env: [String: String] = [:], enable: Bool = true) {
        self.name = name
        self.env = env
        self.enable = enable
    }
}

/// The answer to a catalog install. `background` means a git clone and build runs on the server; `action` names it.
public struct MCPCatalogInstallResult: Sendable, Equatable, Codable {
    /// True when the install was accepted.
    public var ok: Bool?
    /// Entry name.
    public var name: String?
    /// True when the install runs in the background.
    public var background: Bool?
    /// Name of the background action.
    public var action: String?
}
