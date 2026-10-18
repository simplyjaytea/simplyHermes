#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > MCP servers. Adding a server is the one change this screen sends for now. The servers
    /// already in config are read after an add but not shown here yet. Their switches, tests, removals, catalog and
    /// sign-ins are not on this screen (WP-53b).
    public struct MCPServersView: View {
        @State private var model: MCPServersModel
        @State private var showsAdd = false

        public init(connections: ConnectionsModel) {
            _model = State(initialValue: MCPServersModel(connections: connections))
        }

        init(model: MCPServersModel) {
            _model = State(initialValue: model)
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
            }
            .navigationTitle("MCP servers")
            .sheet(isPresented: $showsAdd) {
                MCPServerFormView(model: model) { showsAdd = false }
            }
        }
    }

    #Preview("MCP servers, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { MCPServersView(model: .preview()) }
    }

    #Preview("MCP servers, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { MCPServersView(model: .preview()) }
    }

    #Preview("MCP servers, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { MCPServersView(model: .preview()) }
    }

    #Preview("MCP servers, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { MCPServersView(model: .preview()) }
    }
#endif
