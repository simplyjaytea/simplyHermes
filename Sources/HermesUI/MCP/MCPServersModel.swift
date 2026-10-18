#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The MCP servers in config, on the active server (WP-53b). The list is read on screen. Add, Test and Remove each
    /// send one change, check only its HTTP status, then read the list again. A test's own answer is not read.
    @MainActor
    @Observable
    public final class MCPServersModel {
        /// The servers in config, in the server's order.
        public private(set) var servers: [MCPServerInfo] = []
        public private(set) var isLoading = false
        /// Set when a read or a change failed. The list on screen stays.
        public private(set) var errorText: String?
        /// Set after a change the server accepted: one sentence.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `servers` seeds the list, for previews.
        public init(connections: ConnectionsModel, servers: [MCPServerInfo] = []) {
            self.connections = connections
            self.servers = servers
        }

        /// Reads the list. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                servers = try await rest.mcpServers()
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Adds a server, then reads the list again. Throws the server's own answer when it refuses, for example a name
        /// that is taken. A failed read after a successful add does not fail the add.
        public func add(_ server: MCPServerCreate) async throws {
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.addMCPServer(server)
            notice = "Added \(server.name)."
            await refresh()
        }

        /// Sends a test of one server, then reads the list again. Only the HTTP status is checked, so the notice says
        /// that the test was sent and not that it passed.
        public func test(_ server: MCPServerInfo) async {
            let note = "Test sent for \(server.name). This screen doesn't show the result yet."
            await change(success: note) { rest in
                try await rest.testMCPServer(server.name)
            }
        }

        /// Removes a server from config, then reads the list again.
        public func remove(_ server: MCPServerInfo) async {
            await change(success: "Removed \(server.name).") { rest in
                try await rest.removeMCPServer(named: server.name)
            }
        }

        /// Runs one change, then reads the list again. A refusal shows the server's sentence.
        private func change(success: String, _ action: (RESTClient) async throws -> Void) async {
            notice = nil
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                try await action(rest)
                notice = success
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
            await refresh()
        }
    }

    extension MCPServersModel {
        /// A model with sample servers, for previews. It never reaches a server.
        static func preview() -> MCPServersModel {
            MCPServersModel(connections: .preview(), servers: ToolsetAdminSamples.mcpServers)
        }
    }
#endif
