#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Terminal tool: a rail of tabs, each a Hermes TUI session on the server, and the selected tab's pane.
    struct TerminalScreen: View {
        let connections: ConnectionsModel?
        let terminals: TerminalModel
        let addToChat: (String) -> Void

        @State private var connector: TerminalConnector?
        @State private var profile: String?
        @State private var unavailable: String?

        var body: some View {
            Group {
                if let connections, let active = connections.active {
                    VStack(spacing: 0) {
                        tabRail
                        pane(for: active)
                    }
                } else {
                    ContentUnavailableView(
                        "No server connected", systemImage: "terminal",
                        description: Text("Connect a server to open a terminal."))
                }
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Terminal", systemImage: "plus") { terminals.open() }
                        .disabled(connections?.active == nil)
                }
            }
            .task(id: connections?.active?.id) { await resolveConnector() }
        }

        @ViewBuilder
        private var tabRail: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(terminals.tabs.tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }

        private func tabChip(_ tab: TerminalTab) -> some View {
            let isSelected = terminals.tabs.selectedID == tab.id
            return Button {
                terminals.select(tab.id)
            } label: {
                Text(tab.title)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: HermesMetrics.minTapTarget)
                    .background(isSelected ? HermesColor.accent : HermesColor.fill, in: Capsule())
                    .foregroundStyle(isSelected ? HermesColor.onAccent : HermesColor.primaryText)
            }
            .contextMenu {
                Button("Close Tab", systemImage: "xmark", role: .destructive) { terminals.close(tab.id) }
            }
        }

        @ViewBuilder
        private func pane(for active: ServerConnection) -> some View {
            if let tab = terminals.tabs.selected {
                if let connector {
                    TerminalPane(
                        tab: tab, connector: connector, profile: profile, terminals: terminals,
                        addToChat: addToChat
                    )
                    // A new identity per attempt gives the pane a fresh socket and a fresh view.
                    .id("\(tab.id)-\(terminals.attempt(of: tab.id))")
                } else if let unavailable {
                    ContentUnavailableView(
                        "Terminal unavailable", systemImage: "exclamationmark.triangle",
                        description: Text(unavailable))
                } else {
                    ProgressView("Connecting to \(active.name)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("No terminal open", systemImage: "terminal")
                } description: {
                    Text("Open a terminal to run Hermes here. Sessions keep running while you are away.")
                } actions: {
                    Button("New Terminal") { terminals.open() }
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                }
            }
        }

        /// Connects the server if needed and reads the endpoint, credentials and profile the terminal uses.
        private func resolveConnector() async {
            guard let connections, let manager = connections.manager, let active = connections.active else {
                connector = nil
                return
            }
            do {
                connector = try await manager.terminalConnector(
                    for: active, transport: URLSessionTerminalSocketTransport())
                profile = await manager.profile(of: active.id)
                unavailable = nil
            } catch {
                connector = nil
                unavailable = "The server did not connect. Check the server in Settings."
            }
        }
    }
#endif
