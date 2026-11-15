#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The status pill in a chat's header: a symbol and a title, taken from `PillPresentation`. It reads the chat's
    /// status, so it can't say something the composer doesn't do. The full title shows where there is room (UX spec §2.1).
    /// Only the symbol takes the state's ink; the text is always the primary text colour (spec §2.2).
    ///
    /// When the chat is healthy and connected the pill shows only its symbol, so a working chat is quiet. Every other
    /// state keeps its symbol and short title, so a problem stays loud. The pill is a button: it opens a small popover
    /// with the server's name and the full state. VoiceOver always gets the full label.
    public struct StatusPill: View {
        let pill: PillState
        let serverName: String
        @Environment(\.hermesPalette) private var palette
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride
        @State private var showsDetails = false

        public init(pill: PillState, serverName: String) {
            self.pill = pill
            self.serverName = serverName
        }

        public var body: some View {
            Button {
                showsDetails = true
            } label: {
                chip
                    .frame(minHeight: HermesMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.hermesPress)
            .popover(isPresented: $showsDetails) { details.presentationCompactAdaptation(.popover) }
            .accessibilityLabel(Text(PillPresentation.voiceOverLabel(pill, serverName: serverName)))
            .accessibilityHint(Text("Shows details about this chat."))
            .accessibilityIdentifier("chat.pill")
            .onChange(of: pillKey) { _, _ in
                // VoiceOver hears the states that matter as they are entered (O4, L3, L4 and a changed host key).
                guard PillPresentation.announcesOnEntry(pill) else { return }
                AccessibilityNotification.Announcement(
                    PillPresentation.voiceOverLabel(pill, serverName: serverName)
                ).post()
            }
            .sensoryFeedback(.warning, trigger: pillKey) { _, _ in PillPresentation.warnsOnEntry(pill) }
        }

        /// The capsule: the symbol alone while connected, the symbol and a title in every other state.
        private var chip: some View {
            Group {
                if pill == .connected {
                    symbolView
                } else {
                    ViewThatFits(in: .horizontal) {
                        label(PillPresentation.fullTitle(pill, serverName: serverName))
                        label(PillPresentation.shortTitle(pill, serverName: serverName))
                    }
                }
            }
            .font(HermesFont.caption.weight(.semibold))
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(Capsule().fill(ink.opacity(PresetPaletteDefinition.pillTintAlpha)))
        }

        /// What the popover says: the server and the full state, and nothing else.
        private var details: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(serverName)
                    .font(HermesFont.footnote.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(PillPresentation.fullTitle(pill, serverName: serverName))
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .frame(minWidth: 200, alignment: .leading)
        }

        private var symbolView: some View {
            Image(systemName: PillPresentation.symbol(pill))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ink)
                .symbolEffect(.rotate, isActive: motion && isWorking)
                .symbolEffect(.pulse, options: .nonRepeating, value: motion && pill == .unreachable ? pillKey : "")
        }

        private func label(_ title: String) -> some View {
            HStack(spacing: 6) {
                symbolView
                Text(title)
                    .lineLimit(1)
            }
        }

        /// The colour of the pill's family, from the preset. Neutral uses the secondary text colour.
        private var ink: Color {
            switch PillPresentation.ink(pill) {
            case .online: palette.statusOnlineInk
            case .warning: palette.statusWarningInk
            case .problem: palette.statusProblemInk
            case .local: palette.statusLocalInk
            case .neutral: palette.secondaryText
            }
        }

        /// Motion turns off with Reduce Motion, from the system or the app's own setting.
        private var motion: Bool {
            !HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        private var isWorking: Bool { pill == .connecting || pill == .reconnecting }

        private var pillKey: String { PillPresentation.shortTitle(pill, serverName: serverName) }
    }
#endif
