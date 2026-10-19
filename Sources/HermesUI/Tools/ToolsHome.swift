#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools tab (plan Q38): one list of tools. Terminal is here. Each work package adds its own rows: WP-54 adds
    /// Logs and Usage, and WP-55 adds Kanban.
    public struct ToolsHome: View {
        private let connections: ConnectionsModel
        private let terminals: TerminalModel
        private let addToChat: (String) -> Void

        init(connections: ConnectionsModel, terminals: TerminalModel, addToChat: @escaping (String) -> Void) {
            self.connections = connections
            self.terminals = terminals
            self.addToChat = addToChat
        }

        public var body: some View {
            List {
                Section {
                    NavigationLink {
                        TerminalScreen(connections: connections, terminals: terminals, addToChat: addToChat)
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                    NavigationLink {
                        ServerLogsScreen(connections: connections)
                    } label: {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("tools.logs")
                    NavigationLink {
                        ServerAnalyticsScreen(connections: connections)
                    } label: {
                        Label("Usage", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityIdentifier("tools.usage")
                }
            }
            .navigationTitle("Tools")
        }
    }

    #Preview("Tools, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ToolsHome(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in })
        }
    }

    #Preview("Tools, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ToolsHome(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in })
        }
    }

    #Preview("Tools, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ToolsHome(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in })
        }
    }

    #Preview("Tools, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ToolsHome(connections: .preview([]), terminals: TerminalModel(), addToChat: { _ in })
        }
    }
#endif
