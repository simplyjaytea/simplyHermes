import Foundation

/// One MCP server from `GET /api/mcp/servers`. Typed from `Fixtures/rest/GET_api_mcp_servers.seeded.json`. `url`,
/// `args`, `auth`, `env`, `plugin` and `tools` are null or empty in that answer, so they have no type here until a
/// fixture shows one.
public struct MCPServerInfo: Sendable, Equatable, Codable, Identifiable {
    /// Server name. Unique in the profile.
    public var name: String
    /// Kind of transport, such as `stdio`.
    public var transport: String?
    /// Program a `stdio` server starts.
    public var command: String?
    /// True when the server is switched on.
    public var enabled: Bool
    /// Where the server is defined, such as `config`.
    public var source: String?

    /// Identity for lists.
    public var id: String { name }
}

/// `GET /api/mcp/servers`: every server in the profile. Typed from `Fixtures/rest/GET_api_mcp_servers.seeded.json`.
/// The empty answer in `GET_api_mcp_servers.json` gives no field evidence.
public struct MCPServerList: Sendable, Equatable, Codable {
    /// The servers.
    public var servers: [MCPServerInfo]
}

/// `POST /api/mcp/servers/{name}/test`: the answer of a test. Typed from
/// `Fixtures/rest/POST_api_mcp_servers_recorder-mcp_test.json`, which holds a failed test: `ok` is false and
/// `error` is the server's own words. No recording holds a passed test, so `ok` true is unverified until a real
/// server runs one. `tools` is an empty list in that answer, and prompts and resources do not appear in it, so they
/// have no type here.
public struct MCPTestResult: Sendable, Equatable, Codable {
    /// True when the test passed. Unverified for `true`.
    public var ok: Bool?
    /// Why the test failed, in the server's own words.
    public var error: String?
}

/// `GET /api/mcp/catalog`: the catalog entries. Typed from `Fixtures/rest/GET_api_mcp_catalog.json`. Its `diagnostics`
/// list is empty in that answer, so it has no type here.
public struct MCPCatalog: Sendable, Equatable, Codable {
    /// Catalog entries.
    public var entries: [MCPCatalogEntry]
}

/// One catalog entry, typed from `Fixtures/rest/GET_api_mcp_catalog.json`. `command`, `args`, `install_url` and
/// `install_ref` are null or empty in every recorded entry, so they have no type here.
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
    /// Address the server uses (HTTP).
    public var url: String?
    /// Text the server shows after the install.
    public var postInstall: String?
    /// True when the entry needs an install step first.
    public var needsInstall: Bool?
    /// True when the entry is already in config.
    public var installed: Bool?
    /// True when the installed entry is switched on.
    public var enabled: Bool?

    /// Identity for lists.
    public var id: String { name }
}

/// A variable a catalog entry asks for, typed from `Fixtures/rest/GET_api_mcp_catalog.json`. The value is entered once
/// and never read back.
public struct MCPCatalogEnvVar: Sendable, Equatable, Codable {
    /// Variable name.
    public var name: String
    /// Label the server suggests for the value.
    public var prompt: String?
    /// True when the entry cannot work without it.
    public var required: Bool?
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
