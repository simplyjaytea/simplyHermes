#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The strip above the composer (plan Q27): a context ring with the percent used, a connection dot, and the
    /// token breakdown in a popover.
    struct ChatStatusBar: View {
        let strip: ChatStatusStrip
        /// The chat's pill. It replaces the bare connection dot, so the strip and the pill can't disagree.
        let pill: PillState
        let serverName: String
        @State private var showsDetails = false
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            // The pill sits beside the button, not inside it: a button merges its contents into one accessibility element,
            // so inside it the pill's own label and identifier would never be seen (WP-8).
            HStack(spacing: 8) {
                Button {
                    showsDetails = true
                } label: {
                    HStack(spacing: 8) {
                        ContextRing(percent: strip.contextPercent, level: strip.contextLevel)
                            .frame(width: 18, height: 18)
                        if let context = strip.reading(.context) {
                            Text(context.value)
                                .font(HermesFont.caption.monospacedDigit())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.status")
                .accessibilityLabel(Text(accessibilityText))
                .accessibilityHint(Text("Shows token details"))
                .popover(isPresented: $showsDetails) { details.presentationCompactAdaptation(.popover) }
                StatusPill(pill: pill, serverName: serverName)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
        }

        private var accessibilityText: String {
            let readings = strip.readings(ChatStatusStrip.defaultItems)
            return readings.map { "\($0.item.rawValue) \($0.value)" }.joined(separator: ", ")
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(strip.readings(ChatStatusStrip.defaultItems + [.tokens, .cost])) { reading in
                    HStack {
                        Text(reading.item.rawValue.capitalized)
                            .foregroundStyle(palette.secondaryText)
                        Spacer(minLength: 16)
                        Text(reading.estimated ? "~\(reading.value)" : reading.value)
                    }
                    .font(HermesFont.footnote)
                }
                if strip.readings(ChatStatusStrip.defaultItems).isEmpty {
                    Text("No usage yet").font(HermesFont.footnote).foregroundStyle(palette.secondaryText)
                }
            }
            .padding(16)
            .frame(minWidth: 220)
        }
    }

    /// A thin ring that fills with the context window. Turns orange at 75% and red at 90%.
    struct ContextRing: View {
        let percent: Double?
        let level: ContextLevel?
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            ZStack {
                Circle().stroke(palette.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .accessibilityHidden(true)
        }

        private var color: Color {
            switch level {
            case .critical?: palette.destructive
            case .warning?: palette.statusWarning
            default: palette.accent
            }
        }
    }
#endif
