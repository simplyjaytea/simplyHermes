#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > MCP servers. Adding a server and installing from the catalog are the changes this screen
    /// sends for now. The servers already in config are read after an add but not shown here yet. Their switches, tests,
    /// removals and sign-ins are not on this screen (WP-53b).
    public struct MCPServersView: View {
        @State private var model: MCPServersModel
        @State private var catalog: MCPCatalogModel
        @State private var showsAdd = false

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: MCPServersModel(connections: connections))
            _catalog = State(initialValue: MCPCatalogModel(connections: connections))
        }

        init(model: MCPServersModel, catalog: MCPCatalogModel) {
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
                Section {
                    Button {
                        showsAdd = true
                    } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .accessibilityIdentifier("mcp.add")
                } footer: {
                    Text("Servers already in config are not listed here yet.")
                }
                catalogSection
            }
            .navigationTitle("MCP servers")
            .sheet(isPresented: $showsAdd) {
                MCPServerFormView(model: model) { showsAdd = false }
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
    }

    #Preview("MCP servers, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { MCPServersView(model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { MCPServersView(model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { MCPServersView(model: .preview(), catalog: .preview()) }
    }

    #Preview("MCP servers, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { MCPServersView(model: .preview(), catalog: .preview()) }
    }
#endif
