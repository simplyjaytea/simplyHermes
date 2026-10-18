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

/// MCP servers, their OAuth sign-in and the catalog. The answers that the screens ignore are not decoded.
extension RESTClient {
    /// `GET /api/mcp/servers`.
    public func mcpServers() async throws -> [MCPServerInfo] {
        let list: MCPServerList = try await get("/api/mcp/servers")
        return list.servers
    }

    /// `POST /api/mcp/servers`: adds a server to config. Refuses a name that exists.
    public func addMCPServer(_ server: MCPServerCreate) async throws {
        let _: HTTPResponse = try await send("POST", "/api/mcp/servers", body: server)
    }

    /// `PUT /api/mcp/servers`: replaces every entry of the `mcp_servers` map with `servers`.
    ///
    /// Send the complete map, built from the full config. ``mcpServers()`` masks env values, so never build the map
    /// from it, or the masked values would be written back.
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

    /// `POST /api/mcp/servers/{name}/test`: connects, lists the tools and disconnects.
    public func testMCPServer(_ name: String) async throws -> MCPServerTestResult {
        try await send("POST", "/api/mcp/servers/" + mcpPath(name, "test"))
    }

    /// `POST /api/mcp/servers/{name}/auth`: starts an OAuth sign-in. Open ``MCPOAuthFlow/authorizationUrl`` in a
    /// browser, then poll ``mcpOAuthFlow(id:)`` until ``MCPOAuthFlow/isFinished``.
    public func startMCPServerAuth(_ name: String) async throws -> MCPOAuthFlow {
        try await send("POST", "/api/mcp/servers/" + mcpPath(name, "auth"))
    }

    /// `GET /api/mcp/oauth/flows/{flow_id}`. A flow that expired answers 404.
    public func mcpOAuthFlow(id: String) async throws -> MCPOAuthFlow {
        try await get("/api/mcp/oauth/flows/" + mcpPath(id))
    }

    /// `DELETE /api/mcp/oauth/flows/{flow_id}`: abandons a sign-in. Safe to call after the flow finished.
    public func cancelMCPOAuthFlow(id: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/mcp/oauth/flows/" + mcpPath(id))
    }

    /// `GET /api/mcp/catalog`.
    public func mcpCatalog() async throws -> MCPCatalog {
        try await get("/api/mcp/catalog")
    }

    /// `POST /api/mcp/catalog/install`. Only the variables the entry declares are accepted.
    public func installMCPCatalogEntry(_ install: MCPCatalogInstall) async throws -> MCPCatalogInstallResult {
        try await send("POST", "/api/mcp/catalog/install", body: install)
    }
}
