#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools tab (Q38): Skills and Memory. Tools stays minimal. Terminal, Git, Kanban and Logs add a section each
    /// below these, the same way.
    public struct ToolsView: View {
        private let connections: ConnectionsModel?

        /// `connections` is nil when the shell has none. The screens then say that no server is connected.
        public init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        public var body: some View {
            List {
                capabilitiesSection
                memorySection
            }
            .navigationTitle("Tools")
        }

        private var capabilitiesSection: some View {
            Section {
                NavigationLink {
                    SkillsScreen(connections: connections)
                } label: {
                    Label("Skills", systemImage: "sparkles")
                }
                .accessibilityIdentifier("tools.skills")
                NavigationLink {
                    ToolsetsScreen(connections: connections)
                } label: {
                    Label("Toolsets", systemImage: "wrench.and.screwdriver")
                }
                .accessibilityIdentifier("tools.toolsets")
                NavigationLink {
                    AgentPluginsScreen(connections: connections)
                } label: {
                    Label("Agent plugins", systemImage: "puzzlepiece.extension")
                }
                .accessibilityIdentifier("tools.plugins")
            } footer: {
                Text("Skills, toolsets and agent plugins on the server.")
            }
        }

        private var memorySection: some View {
            Section {
                NavigationLink {
                    MemoryJourneyScreen()
                } label: {
                    Label("Memory", systemImage: "brain.head.profile")
                }
                .accessibilityIdentifier("tools.memory")
            }
        }
    }

    #Preview("Tools, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ToolsView(connections: .preview()) }
    }

    #Preview("Tools, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ToolsView(connections: .preview()) }
    }

    #Preview("Tools, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ToolsView(connections: .preview()) }
    }

    #Preview("Tools, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ToolsView(connections: .preview()) }
    }
#endif
