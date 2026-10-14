#if canImport(UIKit)
    import SwiftUI

    /// Three bouncing dots in a Hermes bubble, shown while a turn starts and no text has arrived yet.
    /// With Reduce Motion on, the dots only fade.
    public struct TypingIndicator: View {
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        public init() {}

        public var body: some View {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    TypingDot(index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 14)
            .background(HermesColor.incomingBubble, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Hermes is working"))
            .bubbleRow(.leading)
        }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }
    }

    private struct TypingDot: View {
        let index: Int
        let reduceMotion: Bool

        var body: some View {
            Circle()
                .fill(HermesColor.secondaryText)
                .frame(width: 8, height: 8)
                .phaseAnimator([false, true]) { content, lifted in
                    content
                        .offset(y: lifted && !reduceMotion ? -4 : 0)
                        .opacity(lifted ? 1 : 0.4)
                } animation: { _ in
                    .easeInOut(duration: 0.45).delay(Double(index) * 0.15)
                }
        }
    }

    /// Hermes reply text while it streams in, with a pulsing caret at the end.
    /// Incremental markdown and per-token effects come with the transcript (plan WP-30).
    public struct StreamingText: View {
        private let text: String
        private let isStreaming: Bool

        public init(text: String, isStreaming: Bool) {
            self.text = text
            self.isStreaming = isStreaming
        }

        public var body: some View {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(text)
                    .font(HermesFont.bubble)
                    .foregroundStyle(HermesColor.primaryText)
                if isStreaming {
                    StreamingCaret()
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, HermesMetrics.bubbleVerticalPadding)
            .background(
                HermesColor.incomingBubble,
                in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
            )
            .bubbleRow(.leading)
        }
    }

    /// A small accent capsule that pulses while text streams. Fades only with Reduce Motion on.
    public struct StreamingCaret: View {
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        public init() {}

        public var body: some View {
            Capsule()
                .fill(HermesColor.accent)
                .frame(width: 8, height: 14)
                .phaseAnimator([false, true]) { content, pulsing in
                    content
                        .opacity(pulsing ? 1 : 0.35)
                        .scaleEffect(pulsing && !reduceMotion ? 1 : 0.8, anchor: .bottom)
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
                .accessibilityHidden(true)
        }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }
    }
#endif
