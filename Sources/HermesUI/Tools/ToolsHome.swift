#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools tab. Each work package adds its own rows to the section: WP-54 adds Logs and Usage, and WP-55 adds
    /// Kanban.
    public struct ToolsHome: View {
        private let connections: ConnectionsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        public var body: some View {
            List {
                Section {
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
            ToolsHome(connections: .preview())
        }
    }

    #Preview("Tools, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ToolsHome(connections: .preview())
        }
    }

    #Preview("Tools, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ToolsHome(connections: .preview())
        }
    }

    #Preview("Tools, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ToolsHome(connections: .preview([]))
        }
    }
#endif
