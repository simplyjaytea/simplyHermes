#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The strip above the composer (plan Q27): a context ring with the percent used, a connection dot, and the
    /// token breakdown in a popover.
    struct ChatStatusBar: View {
        let strip: HermesKit.StatusStrip
        @State private var showsDetails = false

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
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.status")
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(Text("Shows token details"))
            .popover(isPresented: $showsDetails) { details.presentationCompactAdaptation(.popover) }
        }

        private var dotColor: Color {
            switch strip.connection {
            case .online: HermesColor.statusConnected
            case .reconnecting, .needsAttention: HermesColor.statusWarning
            case .offline: HermesColor.statusOffline
            }
        }

        private var accessibilityText: String {
            let readings = strip.readings(HermesKit.StatusStrip.defaultItems)
            return readings.map { "\($0.item.rawValue) \($0.value)" }.joined(separator: ", ")
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(strip.readings(HermesKit.StatusStrip.defaultItems + [.tokens, .cost])) { reading in
                    HStack {
                        Text(reading.item.rawValue.capitalized)
                            .foregroundStyle(HermesColor.secondaryText)
                        Spacer(minLength: 16)
                        Text(reading.estimated ? "~\(reading.value)" : reading.value)
                    }
                    .font(HermesFont.footnote)
                }
                if strip.readings(HermesKit.StatusStrip.defaultItems).isEmpty {
                    Text("No usage yet").font(HermesFont.footnote).foregroundStyle(HermesColor.secondaryText)
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

        var body: some View {
            ZStack {
                Circle().stroke(HermesColor.fill, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .accessibilityHidden(true)
        }

        private var color: Color {
            switch level {
            case .critical?: HermesColor.destructive
            case .warning?: HermesColor.statusWarning
            default: HermesColor.accent
            }
        }
    }
#endif
