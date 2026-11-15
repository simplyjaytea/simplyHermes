#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The context ring with the percent used. It opens the token breakdown in a popover. It is the second item of the
    /// chat's bottom info row (plan Q27).
    struct ContextButton: View {
        let strip: ChatStatusStrip
        @State private var showsDetails = false
        @Environment(\.hermesPalette) private var palette

        var body: some View {
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
                .frame(minWidth: HermesMetrics.minTapTarget, minHeight: HermesMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.hermesPress)
            .accessibilityIdentifier("chat.status")
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(Text("Shows token details"))
            .popover(isPresented: $showsDetails) { details.presentationCompactAdaptation(.popover) }
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
