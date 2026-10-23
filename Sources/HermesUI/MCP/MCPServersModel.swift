#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The MCP servers in config, on the active server (WP-53b). The list is read on screen. Add and Remove send one
    /// change each and check only its HTTP status. Test shows the answer the server gives. Each change reads the list
    /// again.
    @MainActor
    @Observable
    public final class MCPServersModel {
        /// The servers in config, in the server's order.
        public private(set) var servers: [MCPServerInfo] = []
        public private(set) var isLoading = false
        /// Set when the list could not be read. The list on screen stays.
        public private(set) var readErrorText: String?
        /// Set when a change or a test failed. A failed test shows the server's own words.
        public private(set) var errorText: String?
        /// Set after a change the server accepted, or a test that passed: one sentence.
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
                readErrorText = nil
            } catch is CancellationError {
                return
            } catch {
                readErrorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Adds a server, then reads the list again. Throws the server's own answer when it refuses, for example a name
        /// that is taken. A failed read after a successful add does not fail the add.
        public func add(_ server: MCPServerCreate) async throws {
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.addMCPServer(server)
            errorText = nil
            notice = "Added \(server.name)."
            await refresh()
        }

        /// Runs a test and shows its answer, then reads the list again. A failed test shows the server's error text.
        /// A passed test is not in any recording, so its sentence is unverified until a real server runs one.
        public func test(_ server: MCPServerInfo) async {
            notice = nil
            errorText = nil
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                let result = try await rest.testMCPServer(server.name)
                if result.ok == true {
                    // Unverified: no recording holds a passed test. Needs a real server [JT].
                    notice = "\(server.name) passed the test."
                } else if result.ok == false {
                    let reason = result.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    errorText = reason.isEmpty ? "\(server.name) failed the test." : reason
                } else {
                    notice = "Test sent for \(server.name). The result is not shown here yet."
                }
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
            await refresh()
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
            errorText = nil
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                try await action(rest)
                notice = success
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
