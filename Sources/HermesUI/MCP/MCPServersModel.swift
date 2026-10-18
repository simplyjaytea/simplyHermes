#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The MCP servers of the active server's profile: list, switch, test, sign in, remove and add (WP-53b).
    ///
    /// Every change goes to the server, then the list is read again, so the screen shows what the server now has.
    /// Plugin servers are read-only here.
    @MainActor
    @Observable
    public final class MCPServersModel {
        public private(set) var servers: [MCPServerInfo] = []
        public private(set) var isLoading = false
        /// Set when the last refresh or change failed. The list on screen stays.
        public private(set) var errorText: String?
        /// Outcome of the last test, as a sentence, by server name.
        public private(set) var testResults: [String: String] = [:]
        /// The OAuth sign-in in progress, if any.
        public private(set) var signIn: MCPOAuthFlow?
        /// Switch values sent to the server and not answered yet, by server name.
        private var pendingEnabled: [String: Bool] = [:]
        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private var pollTask: Task<Void, Never>?

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

        /// The switch to show: the value being sent, or else the stored one.
        public func isEnabled(_ server: MCPServerInfo) -> Bool {
            pendingEnabled[server.name] ?? server.enabled
        }

        /// True while a switch of this server is being sent.
        public func isChanging(_ server: MCPServerInfo) -> Bool {
            pendingEnabled[server.name] != nil
        }

        /// Switches a server on or off. The change applies to the next session.
        public func setEnabled(_ server: MCPServerInfo, _ enabled: Bool) async {
            guard server.isEditable else { return }
            pendingEnabled[server.name] = enabled
            defer { pendingEnabled[server.name] = nil }
            await change { try await $0.setMCPServerEnabled(server.name, enabled: enabled) }
        }

        /// Removes a server from config.
        public func remove(_ server: MCPServerInfo) async {
            guard server.isEditable else { return }
            await change { try await $0.removeMCPServer(named: server.name) }
            testResults[server.name] = nil
        }

        /// Adds a server. Throws the server's own answer when it refuses, for example a name that is taken.
        public func add(_ server: MCPServerCreate) async throws {
            let rest = try await ToolsetAdminClient.rest(connections)
            try await rest.addMCPServer(server)
            await refresh()
        }

        /// Connects to a server and lists its tools. The outcome shows on the server's row.
        public func test(_ server: MCPServerInfo) async {
            testResults[server.name] = "Testing…"
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                let result = try await rest.testMCPServer(server.name)
                testResults[server.name] = Self.summary(of: result)
            } catch {
                testResults[server.name] = ToolsetAdminClient.message(for: error)
            }
        }

        /// Starts an OAuth sign-in. Returns the page the user opens in a browser. The model then polls the flow until
        /// it ends, so the caller only opens the page.
        public func startSignIn(_ server: MCPServerInfo) async -> URL? {
            guard server.isEditable, server.supportsOAuth else { return nil }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                let flow = try await rest.startMCPServerAuth(server.name)
                if flow.isFinished {
                    finish(flow)
                    return nil
                }
                guard let text = flow.authorizationUrl, let page = URL(string: text) else {
                    errorText = "The server did not give a sign-in page."
                    return nil
                }
                errorText = nil
                signIn = flow
                pollTask?.cancel()
                pollTask = Task { await poll(flowID: flow.flowId) }
                return page
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
                return nil
            }
        }

        /// Abandons the sign-in in progress.
        public func cancelSignIn() async {
            pollTask?.cancel()
            pollTask = nil
            guard let flow = signIn else { return }
            signIn = nil
            if let rest = try? await ToolsetAdminClient.rest(connections) {
                _ = try? await rest.cancelMCPOAuthFlow(id: flow.flowId)
            }
        }

        /// Runs one change, then reads the list again.
        private func change(_ action: (RESTClient) async throws -> Void) async {
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                try await action(rest)
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
            await refresh()
        }

        /// Reads the flow every two seconds until it ends, or about five minutes pass.
        private func poll(flowID: String) async {
            for _ in 0..<150 {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let rest = try? await ToolsetAdminClient.rest(connections),
                    let flow = try? await rest.mcpOAuthFlow(id: flowID)
                else { continue }
                if flow.isFinished {
                    finish(flow)
                    return
                }
                signIn = flow
            }
            signIn = nil
            errorText = "The sign-in timed out. Start it again."
        }

        /// Ends the sign-in: approved servers are read again, failed ones show the reason.
        private func finish(_ flow: MCPOAuthFlow) {
            signIn = nil
            if flow.isApproved {
                errorText = nil
                Task { await refresh() }
            } else {
                errorText = flow.error ?? "The sign-in did not finish."
            }
        }

        private static func summary(of result: MCPServerTestResult) -> String {
            guard result.ok else { return result.error ?? "The server did not answer." }
            let count = result.tools?.count ?? 0
            return count == 1 ? "Connected. 1 tool." : "Connected. \(count) tools."
        }
    }

    extension MCPServersModel {
        /// A model with sample servers, for previews. It never reaches a server.
        static func preview() -> MCPServersModel {
            MCPServersModel(connections: .preview(), servers: ToolsetAdminSamples.mcpServers)
        }
    }
#endif
