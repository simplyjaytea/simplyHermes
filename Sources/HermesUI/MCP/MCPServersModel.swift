#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The MCP servers of the active server (WP-53b). Adding a server is the one change this screen sends. The list is
    /// read again after the add, but the screen does not show it yet. The switches, tests, removals, catalog and
    /// sign-ins are not on this screen.
    @MainActor
    @Observable
    public final class MCPServersModel {
        /// Set after an add. The list is not shown yet, so the sentence says so.
        public private(set) var notice: String?
        /// The servers in config, read again after each add. A failed read keeps the list as it was.
        public private(set) var servers: [MCPServerInfo] = []
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model.
        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Adds a server, then reads the list again. Throws the server's own answer when it refuses, for example a name
        /// that is taken. A failed read after a successful add does not fail the add.
        public func add(_ server: MCPServerCreate) async throws {
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.addMCPServer(server)
            notice = "Added \(server.name). The server list is not shown yet."
            if let refreshed = try? await rest.mcpServers() {
                servers = refreshed
            }
        }
    }

    extension MCPServersModel {
        /// A model for previews. It never reaches a server.
        static func preview() -> MCPServersModel {
            MCPServersModel(connections: .preview())
        }
    }
#endif
