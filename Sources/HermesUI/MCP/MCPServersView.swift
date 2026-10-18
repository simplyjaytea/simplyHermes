#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > MCP servers: switch servers on or off, test them, sign in, remove and add (WP-53b).
    ///
    /// Plugin servers are read-only here. Removing a server asks first. A sign-in opens the server's page in the
    /// browser, and the screen then waits for the result.
    public struct MCPServersView: View {
        private let connections: ConnectionsModel
        @State private var model: MCPServersModel
        @State private var catalog: MCPCatalogModel
        @State private var showsAdd = false
        @State private var pendingRemove: MCPServerInfo?
        @Environment(\.openURL) private var openURL

        public init(connections: ConnectionsModel) {
            self.connections = connections
            _model = State(initialValue: MCPServersModel(connections: connections))
            _catalog = State(initialValue: MCPCatalogModel(connections: connections))
        }

        init(connections: ConnectionsModel, model: MCPServersModel, catalog: MCPCatalogModel) {
            self.connections = connections
            _model = State(initialValue: model)
            _catalog = State(initialValue: catalog)
        }

        public var body: some View {
            List {
                if let flow = model.signIn {
                    signInSection(flow)
                }
                serversSection
                catalogSection
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("MCP servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsAdd = true
                    } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .accessibilityIdentifier("mcp.add")
                }
            }
            .overlay { emptyState }
            .refreshable { await model.refresh() }
            .task(id: connections.active?.id) { await model.refresh() }
            .sheet(isPresented: $showsAdd) {
                MCPServerFormView(model: model) { showsAdd = false }
            }
            .confirmationDialog(
                "Remove \(pendingRemove?.name ?? "server")?", isPresented: removeBinding, titleVisibility: .visible,
                presenting: pendingRemove
            ) { server in
                Button("Remove server", role: .destructive) { Task { await model.remove(server) } }
            } message: { _ in
                Text("The server leaves the config on the Hermes server. You can add it again later.")
            }
        }

        private var serversSection: some View {
            Section {
                ForEach(model.servers) { server in
                    MCPServerRow(
                        server: server, isOn: model.isEnabled(server), isBusy: model.isChanging(server),
                        testText: model.testResults[server.name],
                        onSetEnabled: { enabled in Task { await model.setEnabled(server, enabled) } },
                        onTest: { Task { await model.test(server) } },
                        onSignIn: { signIn(server) },
                        onRemove: { pendingRemove = server })
                }
            } header: {
                Text("Servers")
            } footer: {
                Text("A server that is off stays in the config. Changes apply the next time Hermes starts a session.")
            }
        }

        private var catalogSection: some View {
            Section {
                NavigationLink {
                    MCPCatalogView(model: catalog)
                } label: {
                    Label("Install from catalog", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("mcp.catalog")
            } footer: {
                Text("The approved catalog lists servers you can install. Some need a value, such as an access token.")
            }
        }

        private func signInSection(_ flow: MCPOAuthFlow) -> some View {
            Section {
                if let text = flow.authorizationUrl, let page = URL(string: text) {
                    Button("Open sign-in page", systemImage: "safari") { openURL(page) }
                } else {
                    ProgressView("Starting sign-in…")
                }
                Button("Cancel sign-in", systemImage: "xmark.circle") {
                    Task { await model.cancelSignIn() }
                }
            } header: {
                Text("Sign in to \(flow.serverName ?? "a server")")
            } footer: {
                Text("Finish the sign-in in the browser. This screen checks for the result every few seconds.")
            }
        }

        private func signIn(_ server: MCPServerInfo) {
            Task {
                if let page = await model.startSignIn(server) {
                    openURL(page)
                }
            }
        }

        private var removeBinding: Binding<Bool> {
            Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })
        }

        @ViewBuilder private var emptyState: some View {
            if model.servers.isEmpty && model.errorText == nil {
                if connections.active == nil {
                    ContentUnavailableView(
                        "No server", systemImage: "server.rack", description: Text("Add a server under Servers first."))
                } else if model.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No MCP servers", systemImage: "puzzlepiece.extension",
                        description: Text("Add one with +, or install one from the catalog."))
                }
            }
        }
    }

    /// One MCP server: its address or program, the names of its variables, a switch and a menu.
    ///
    /// Variable values are never shown. The server masks them, so only the names reach the screen.
    private struct MCPServerRow: View {
        let server: MCPServerInfo
        /// The switch to show, which is the value being sent while a change is in flight.
        let isOn: Bool
        let isBusy: Bool
        let testText: String?
        let onSetEnabled: (Bool) -> Void
        let onTest: () -> Void
        let onSignIn: () -> Void
        let onRemove: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name).font(HermesFont.body.weight(.semibold))
                    Text(address)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                    if !server.envNames.isEmpty {
                        Text("Variables: " + server.envNames.joined(separator: ", "))
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(2)
                    }
                    if let plugin = server.plugin, !server.isEditable {
                        Text("Provided by the \(plugin) plugin. Read-only here.")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    if let testText {
                        Text(testText)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Toggle("Enabled", isOn: Binding(get: { isOn }, set: onSetEnabled))
                    .labelsHidden()
                    .disabled(!server.isEditable || isBusy)
                    .accessibilityIdentifier("mcp.enabled.\(server.name)")
                menu
            }
            .accessibilityIdentifier("mcp.server.\(server.name)")
        }

        private var menu: some View {
            Menu {
                Button("Test connection", systemImage: "bolt.horizontal.circle", action: onTest)
                if server.isEditable && server.supportsOAuth {
                    Button("Sign in", systemImage: "person.badge.key", action: onSignIn)
                }
                if server.isEditable {
                    Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
            }
            .accessibilityLabel(Text("More for \(server.name)"))
        }

        private var address: String {
            if let url = server.url, !url.isEmpty {
                return url
            }
            let program = [server.command ?? ""] + (server.args ?? [])
            return program.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    #Preview("MCP servers, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { MCPServersView(connections: .preview(), model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { MCPServersView(connections: .preview(), model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { MCPServersView(connections: .preview(), model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { MCPServersView(connections: .preview(), model: .preview(), catalog: .preview()) }
    }
#endif
