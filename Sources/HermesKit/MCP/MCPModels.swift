import Foundation

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
