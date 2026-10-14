#if canImport(UIKit)
    import SwiftUI

    /// Connection state and the running turn, in a Liquid Glass capsule.
    public struct StatusStrip: View {
        public enum Connection: Sendable {
            case connected
            case reconnecting
            case offline
        }

        private let connection: Connection
        private let serverName: String
        private let runningTurn: String?
        private let onStop: (() -> Void)?

        public init(
            connection: Connection,
            serverName: String,
            runningTurn: String? = nil,
            onStop: (() -> Void)? = nil
        ) {
            self.connection = connection
            self.serverName = serverName
            self.runningTurn = runningTurn
            self.onStop = onStop
        }

        public var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(serverName)
                    .font(HermesFont.footnote.weight(.semibold))
                Text(connectionLabel)
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                Spacer(minLength: 8)
                if let runningTurn {
                    Text(runningTurn)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                }
                if let onStop {
                    Button("Stop", action: onStop)
                        .font(HermesFont.footnote.weight(.semibold))
                        .foregroundStyle(HermesColor.accent)
                        .frame(minWidth: HermesMetrics.minTapTarget, minHeight: HermesMetrics.minTapTarget)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: HermesMetrics.minTapTarget)
            .glassEffect(.regular, in: Capsule())
            .accessibilityElement(children: .combine)
        }

        private var dotColor: Color {
            switch connection {
            case .connected: HermesColor.statusConnected
            case .reconnecting: HermesColor.statusWarning
            case .offline: HermesColor.statusOffline
            }
        }

        private var connectionLabel: LocalizedStringKey {
            switch connection {
            case .connected: "Connected"
            case .reconnecting: "Reconnecting…"
            case .offline: "Offline"
            }
        }
    }
#endif
