#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > Toolsets: switch each toolset on or off (WP-53b). A toolset's settings (keys, providers
    /// and models) are not on this screen yet. Their reads are decoded from recorded fixtures.
    public struct ToolsetsView: View {
        private let connections: ConnectionsModel
        @State private var model: ToolsetsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
            _model = State(initialValue: ToolsetsModel(connections: connections))
        }

        init(connections: ConnectionsModel, model: ToolsetsModel) {
            self.connections = connections
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                ForEach(model.toolsets) { toolset in
                    toolsetSection(toolset)
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Toolsets")
            .overlay { emptyState }
            .refreshable { await model.refresh() }
            .task(id: connections.active?.id) { await model.refresh() }
        }

        private func toolsetSection(_ toolset: ToolsetInfo) -> some View {
            Section {
                Toggle(isOn: switchBinding(toolset)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolset.label ?? toolset.name)
                        if let status = statusText(toolset) {
                            Text(status)
                                .font(HermesFont.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                }
                .disabled(model.isChanging(toolset))
                .accessibilityIdentifier("toolset.\(toolset.name)")
            } footer: {
                if let description = toolset.description, !description.isEmpty {
                    Text(description)
                }
            }
        }

        private func switchBinding(_ toolset: ToolsetInfo) -> Binding<Bool> {
            Binding(
                get: { model.isOn(toolset) },
                set: { value in Task { await model.setEnabled(toolset, value) } })
        }

        private func statusText(_ toolset: ToolsetInfo) -> String? {
            if toolset.available == false {
                return "Not available on this server."
            }
            if toolset.configured == false {
                return "Needs setup."
            }
            return nil
        }

        @ViewBuilder private var emptyState: some View {
            if model.toolsets.isEmpty && model.errorText == nil {
                if connections.active == nil {
                    ContentUnavailableView(
                        "No server", systemImage: "server.rack", description: Text("Add a server under Servers first."))
                } else if model.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No toolsets", systemImage: "wrench.and.screwdriver",
                        description: Text("The server lists no toolsets."))
                }
            }
        }
    }

    #Preview("Toolsets, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ToolsetsView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolsets, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ToolsetsView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolsets, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ToolsetsView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolsets, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ToolsetsView(connections: .preview(), model: .preview()) }
    }
#endif
