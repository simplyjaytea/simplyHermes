#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > MCP servers: the servers in config, with Test and Remove, then Add and the catalog
    /// (WP-53b).
    ///
    /// Add and Remove are checked by their HTTP status only. Test shows the answer the server gives. Each change
    /// reads the list again. The switches and sign-ins are not on this screen.
    public struct MCPServersView: View {
        private let connections: ConnectionsModel
        @State private var model: MCPServersModel
        @State private var catalog: MCPCatalogModel
        @State private var showsAdd = false
        @State private var pendingRemove: MCPServerInfo?

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
                if let notice = model.notice {
                    Section {
                        Label(notice, systemImage: "checkmark.circle")
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
                if let readErrorText = model.readErrorText {
                    Section {
                        Label(readErrorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
                serversSection
                Section {
                    Button {
                        showsAdd = true
                    } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .accessibilityIdentifier("mcp.add")
                }
                catalogSection
            }
            .navigationTitle("MCP servers")
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
                if model.servers.isEmpty {
                    emptyRow
                }
                ForEach(model.servers) { server in
                    MCPServerRow(
                        server: server,
                        onTest: { Task { await model.test(server) } },
                        onRemove: { pendingRemove = server })
                }
            } header: {
                Text("In config")
            } footer: {
                Text(
                    "Test checks the server and shows its answer here. "
                        + "Remove deletes the server from the config.")
            }
        }

        @ViewBuilder private var emptyRow: some View {
            if connections.active == nil {
                Text("Add a server under Servers first.")
                    .foregroundStyle(HermesColor.secondaryText)
            } else if model.isLoading {
                ProgressView()
            } else if model.readErrorText == nil {
                Text("No servers in config yet.")
                    .foregroundStyle(HermesColor.secondaryText)
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

        private var removeBinding: Binding<Bool> {
            Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })
        }
    }

    /// One server in config: its name, whether it is on, its transport, its program and where it is defined. A menu
    /// runs Test or Remove. Only the five fields the fixture shows are read here.
    private struct MCPServerRow: View {
        let server: MCPServerInfo
        let onTest: () -> Void
        let onRemove: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name).font(HermesFont.body.weight(.semibold))
                    Text(summary)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                    if let command = server.command, !command.isEmpty {
                        Text(command)
                            .font(HermesFont.codeSmall)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(1)
                    }
                    if let source = server.source, !source.isEmpty {
                        Text("From \(source)")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                menu
            }
            .accessibilityIdentifier("mcp.server.\(server.name)")
        }

        /// Whether the server is on, then its transport when the server reports one.
        private var summary: String {
            let state = server.enabled ? "On" : "Off"
            guard let transport = server.transport, !transport.isEmpty else { return state }
            return "\(state), \(transport)"
        }

        private var menu: some View {
            Menu {
                Button("Test connection", systemImage: "bolt.horizontal.circle", action: onTest)
                    .accessibilityIdentifier("mcp.test.\(server.name)")
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                    .accessibilityIdentifier("mcp.remove.\(server.name)")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("mcp.menu.\(server.name)")
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
