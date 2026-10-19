#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools tab (Q38): Skills, Toolsets and Agent plugins, then Memory and Terminal. Git, Kanban and Logs add a
    /// section each below these, the same way.
    public struct ToolsView: View {
        private let connections: ConnectionsModel?
        private let terminals: TerminalModel
        private let addToChat: (String) -> Void

        /// `connections` is nil when the shell has none. The screens then say that no server is connected.
        init(connections: ConnectionsModel?, terminals: TerminalModel, addToChat: @escaping (String) -> Void) {
            self.connections = connections
            self.terminals = terminals
            self.addToChat = addToChat
        }

        public var body: some View {
            List {
                capabilitiesSection
                memorySection
                terminalSection
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
                    MemoryJourneyScreen(connections: connections)
                } label: {
                    Label("Memory", systemImage: "brain.head.profile")
                }
                .accessibilityIdentifier("tools.memory")
            }
        }

        private var terminalSection: some View {
            Section {
                NavigationLink {
                    TerminalScreen(connections: connections, terminals: terminals, addToChat: addToChat)
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
            }
        }
    }

    #Preview("Tools, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ToolsView(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in }) }
    }

    #Preview("Tools, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ToolsView(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in }) }
    }

    #Preview("Tools, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ToolsView(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in }) }
    }

    #Preview("Tools, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ToolsView(connections: .preview(), terminals: TerminalModel(), addToChat: { _ in }) }
    }
#endif
