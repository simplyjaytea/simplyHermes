#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools & MCP section of Settings: MCP servers, toolsets and capability status (WP-53b).
    struct SettingsToolsSection: View {
        let connections: ConnectionsModel

        var body: some View {
            Section("Tools & MCP") {
                NavigationLink {
                    MCPServersView(connections: connections)
                } label: {
                    Label("MCP servers", systemImage: "puzzlepiece.extension")
                }
                .accessibilityIdentifier("settings.mcpServers")
                NavigationLink {
                    ToolsetsView(connections: connections)
                } label: {
                    Label("Toolsets", systemImage: "wrench.and.screwdriver")
                }
                .accessibilityIdentifier("settings.toolsets")
                NavigationLink {
                    CapabilityStatusView(connections: connections)
                } label: {
                    Label("Capabilities", systemImage: "desktopcomputer")
                }
                .accessibilityIdentifier("settings.capabilities")
            }
        }
    }
#endif
