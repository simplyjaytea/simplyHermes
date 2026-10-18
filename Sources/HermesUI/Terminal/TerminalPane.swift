#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One tab's pane. While it is on screen it holds the tab's socket open; when it goes away the socket closes and
    /// the server keeps the PTY, so the next pane reattaches to the same TUI session.
    struct TerminalPane: View {
        let tab: TerminalTab
        let connector: TerminalConnector
        let profile: String?
        let terminals: TerminalModel
        let addToChat: (String) -> Void

        @Environment(\.colorScheme) private var colorScheme
        @State private var surface = TerminalSurface()

        private var state: TerminalConnectionState? {
            terminals.states[tab.id]
        }

        var body: some View {
            VStack(spacing: 0) {
                statusBar
                TerminalSurfaceView(surface: surface, isDark: colorScheme == .dark)
                    .accessibilityIdentifier("terminal.surface")
                keyRow
            }
            .task { await run() }
        }

        @ViewBuilder
        private var statusBar: some View {
            switch state {
            case .connecting?:
                Label("Connecting", systemImage: "circle.dotted")
                    .font(.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            case .ended?:
                HStack {
                    Text("Session ended")
                        .font(.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                    Spacer()
                    Button("Start again") { terminals.restart(tab.id) }
                        .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            case .failed(let message)?:
                HStack {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                    Spacer()
                    Button("Reconnect") { terminals.restart(tab.id) }
                        .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            case .live?, nil:
                EmptyView()
            }
        }

        /// Keys the touch keyboard lacks, and the way to add the screen to the chat.
        private var keyRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    keyButton("Esc") { surface.press([0x1B]) }
                    keyButton("Tab") { surface.press([0x09]) }
                    keyButton("^C") { surface.press([0x03]) }
                    keyButton("^D") { surface.press([0x04]) }
                    keyButton("\u{2191}") { surface.pressArrow("A") }
                    keyButton("\u{2193}") { surface.pressArrow("B") }
                    keyButton("\u{2192}") { surface.pressArrow("C") }
                    keyButton("\u{2190}") { surface.pressArrow("D") }
                    keyButton("/") { surface.press([0x2F]) }
                    keyButton("|") { surface.press([0x7C]) }
                    keyButton("~") { surface.press([0x7E]) }
                    keyButton("Add to chat") {
                        guard let text = TerminalSnapshot.chatText(lines: surface.screenLines()) else { return }
                        addToChat(text)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }

        private func keyButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title, action: action)
                .font(HermesFont.code.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: HermesMetrics.minTapTarget)
                .background(HermesColor.fill, in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius))
                .foregroundStyle(HermesColor.primaryText)
        }

        /// Opens the socket, feeds the output into the view, and forwards keys and size until the tab leaves the
        /// screen or the server closes the socket.
        private func run() async {
            terminals.report(.connecting, for: tab.id)
            let size = surface.size
            do {
                let connection = try await connector.open(
                    attach: tab.attachToken, profile: profile, columns: size.columns, rows: size.rows)
                terminals.report(.live, for: tab.id)
                let queue = surface.outbound
                let input = Task {
                    for await item in queue.items {
                        switch item {
                        case .keys(let bytes): try? await connection.send(bytes)
                        case .size(let columns, let rows): try? await connection.resize(columns: columns, rows: rows)
                        }
                    }
                }
                defer { input.cancel() }
                try await withTaskCancellationHandler {
                    for try await bytes in connection.output {
                        surface.feed(bytes)
                    }
                } onCancel: {
                    Task { await connection.close() }
                }
                await connection.close()
                if !Task.isCancelled { terminals.report(.ended, for: tab.id) }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                terminals.report(.failed(Self.message(for: error)), for: tab.id)
            }
        }

        private static func message(for error: any Error) -> String {
            switch error {
            case is GatewaySignInRequired:
                "Sign in again to reconnect."
            case WebSocketError.upgradeRejected(let status):
                "The server refused the terminal (\(status))."
            case WebSocketError.closed(let code, _):
                "The terminal closed (\(code.map(String.init) ?? "no code"))."
            default:
                "The terminal lost its connection."
            }
        }
    }
#endif
