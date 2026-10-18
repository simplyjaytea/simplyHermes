import Foundation

private struct MCPEnabledBody: Encodable, Sendable {
    var enabled: Bool
}

/// Joins path parts, percent-encoding each one so a name cannot add a path segment.
private func mcpPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

/// MCP servers, their OAuth sign-in and the catalog. No answer is decoded yet: no recorded fixture shows their fields,
/// so each call checks the HTTP status only (WP-53b).
extension RESTClient {
    /// `POST /api/mcp/servers`: adds a server to config. Refuses a name that exists.
    public func addMCPServer(_ server: MCPServerCreate) async throws {
        let _: HTTPResponse = try await send("POST", "/api/mcp/servers", body: server)
    }

    /// `PUT /api/mcp/servers`: replaces every entry of the `mcp_servers` map with `servers`.
    ///
    /// Send the complete map, built from the full config. The server masks env values in its answers, so never build
    /// the map from an answer, or the masked values would be written back.
    public func replaceMCPServers(_ servers: [String: JSONValue]) async throws {
        let _: HTTPResponse = try await send("PUT", "/api/mcp/servers", body: MCPServersReplace(servers: servers))
    }

    /// `DELETE /api/mcp/servers/{name}`. Plugin servers are refused.
    public func removeMCPServer(named name: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/mcp/servers/" + mcpPath(name))
    }

    /// `PUT /api/mcp/servers/{name}/enabled`. A disabled server stays in config. Takes effect on the next session.
    public func setMCPServerEnabled(_ name: String, enabled: Bool) async throws {
        let _: HTTPResponse = try await send(
            "PUT", "/api/mcp/servers/" + mcpPath(name, "enabled"), body: MCPEnabledBody(enabled: enabled))
    }

    /// `POST /api/mcp/servers/{name}/test`: connects, lists the tools and disconnects. Only the HTTP status is checked.
    public func testMCPServer(_ name: String) async throws {
        let _: HTTPResponse = try await send("POST", "/api/mcp/servers/" + mcpPath(name, "test"))
    }

    /// `POST /api/mcp/servers/{name}/auth`: starts an OAuth sign-in. Only the HTTP status is checked: the flow id and
    /// the sign-in page are not decoded.
    public func startMCPServerAuth(_ name: String) async throws {
        let _: HTTPResponse = try await send("POST", "/api/mcp/servers/" + mcpPath(name, "auth"))
    }

    /// `GET /api/mcp/oauth/flows/{flow_id}`. Only the HTTP status is checked. A flow that expired answers 404.
    public func checkMCPOAuthFlow(id: String) async throws {
        let _: HTTPResponse = try await send("GET", "/api/mcp/oauth/flows/" + mcpPath(id))
    }

    /// `DELETE /api/mcp/oauth/flows/{flow_id}`: abandons a sign-in. Safe to call after the flow finished.
    public func cancelMCPOAuthFlow(id: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/mcp/oauth/flows/" + mcpPath(id))
    }

    /// `POST /api/mcp/catalog/install`. Only the variables the entry declares are accepted. Only the HTTP status is
    /// checked: the answer can say that a build runs in the background, and it is not decoded.
    public func installMCPCatalogEntry(_ install: MCPCatalogInstall) async throws {
        let _: HTTPResponse = try await send("POST", "/api/mcp/catalog/install", body: install)
    }
}
