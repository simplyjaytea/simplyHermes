#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The MCP servers of the active server (WP-53b). Adding a server is the only change sent for now. The list, the
    /// switches, the tests, the removals, the catalog and the sign-ins wait until a recorded fixture shows the answers
    /// they need.
    @MainActor
    @Observable
    public final class MCPServersModel {
        /// Set after an add. The list is not read yet, so the sentence says so.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model.
        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Adds a server. Throws the server's own answer when it refuses, for example a name that is taken.
        public func add(_ server: MCPServerCreate) async throws {
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.addMCPServer(server)
            notice = "Added \(server.name). The server list is not shown yet."
        }
    }

    extension MCPServersModel {
        /// A model for previews. It never reaches a server.
        static func preview() -> MCPServersModel {
            MCPServersModel(connections: .preview())
        }
    }
#endif
