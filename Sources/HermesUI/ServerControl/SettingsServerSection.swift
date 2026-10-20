#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Server section of Settings: gateway control, Hermes update and fleet update (WP-54).
    struct SettingsServerSection: View {
        let connections: ConnectionsModel

        var body: some View {
            Section("Server") {
                NavigationLink {
                    ServerControlScreen(connections: connections)
                } label: {
                    Label("Gateway", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("settings.gateway")
                NavigationLink {
                    HermesUpdateScreen(connections: connections)
                } label: {
                    Label("Hermes update", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("settings.hermesUpdate")
                NavigationLink {
                    FleetUpdateScreen(connections: connections)
                } label: {
                    Label("Update all servers", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("settings.updateAll")
            }
        }
    }
#endif
