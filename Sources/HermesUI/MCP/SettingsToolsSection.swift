#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Tools & MCP section of Settings: MCP servers and capability status (WP-53b). Toolsets live on the Tools tab.
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
                    CapabilityStatusView(connections: connections)
                } label: {
                    Label("Capabilities", systemImage: "desktopcomputer")
                }
                .accessibilityIdentifier("settings.capabilities")
            }
        }
    }
#endif
