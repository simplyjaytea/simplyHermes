#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The status pill in a chat's header: one symbol and one short title, taken from `PillPresentation`. It reads the
    /// chat's status, so it can't say something the composer doesn't do.
    public struct StatusPill: View {
        let pill: PillState
        let serverName: String
        @Environment(\.hermesPalette) private var palette

        public init(pill: PillState, serverName: String) {
            self.pill = pill
            self.serverName = serverName
        }

        public var body: some View {
            HStack(spacing: 6) {
                Image(systemName: PillPresentation.symbol(pill))
                    .symbolRenderingMode(.hierarchical)
                Text(PillPresentation.shortTitle(pill, serverName: serverName))
                    .lineLimit(1)
            }
            .font(HermesFont.caption.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(Capsule().fill(ink.opacity(0.12)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(PillPresentation.voiceOverLabel(pill, serverName: serverName)))
            .accessibilityHint(Text("Shows details about this chat."))
            .accessibilityIdentifier("chat.pill")
            .sensoryFeedback(.warning, trigger: pillKey) { _, _ in PillPresentation.warnsOnEntry(pill) }
        }

        /// The colour for the pill's family. Problem and local are not in the preset palette yet; Moss checks their contrast.
        private var ink: Color {
            switch PillPresentation.ink(pill) {
            case .online: palette.statusConnected
            case .warning: palette.statusWarning
            case .problem: Color(uiColor: .systemRed)
            case .neutral: palette.statusOffline
            case .local: Color(uiColor: .systemPurple)
            }
        }

        private var pillKey: String { PillPresentation.shortTitle(pill, serverName: serverName) }
    }
#endif
