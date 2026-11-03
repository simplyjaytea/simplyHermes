#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    extension StatusStrip.Connection {
        /// The strip's dot for a chat's connection. The chat's status is the source, so the dot can't disagree with the pill.
        init(_ connection: StripConnection) {
            switch connection {
            case .online: self = .connected
            case .reconnecting: self = .reconnecting
            case .offline: self = .offline
            case .needsAttention: self = .needsAttention
            }
        }
    }

    /// Connection state and the running turn, in a Liquid Glass capsule.
    public struct StatusStrip: View {
        public enum Connection: Sendable {
            case connected
            case reconnecting
            case offline
            case needsAttention
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
            case .reconnecting, .needsAttention: HermesColor.statusWarning
            case .offline: HermesColor.statusOffline
            }
        }

        private var connectionLabel: LocalizedStringKey {
            switch connection {
            case .connected: "Connected"
            case .reconnecting: "Reconnecting…"
            case .offline: "Offline"
            case .needsAttention: "Needs attention"
            }
        }
    }
#endif
