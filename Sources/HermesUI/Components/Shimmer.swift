#if canImport(UIKit)
    import SwiftUI

    /// A soft light band that sweeps across a placeholder (plan Q46). With Reduce Motion on it stays still.
    private struct ShimmerModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        func body(content: Content) -> some View {
            if HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride) {
                content.opacity(0.6)
            } else {
                content
                    .phaseAnimator([false, true]) { view, sweeping in
                        view.opacity(sweeping ? 1 : 0.45)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            }
        }
    }

    extension View {
        /// Pulses a placeholder shape while content loads. Under Reduce Motion it is a still, dimmed shape.
        public func hermesShimmer() -> some View { modifier(ShimmerModifier()) }
    }

    /// Placeholder bubbles that stand in for a chat while it loads, instead of a centered spinner (plan Q46).
    public struct TranscriptSkeleton: View {
        public init() {}

        public var body: some View {
            VStack(spacing: HermesMetrics.bubbleSpacing) {
                bubble(width: 0.62, lines: 3, leading: true)
                bubble(width: 0.45, lines: 1, leading: false)
                bubble(width: 0.7, lines: 4, leading: true)
                bubble(width: 0.35, lines: 1, leading: false)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .hermesShimmer()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading chat"))
            .accessibilityIdentifier("transcript.loading")
        }

        private func bubble(width: CGFloat, lines: Int, leading: Bool) -> some View {
            HStack {
                if !leading { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<lines, id: \.self) { index in
                        Capsule()
                            .fill(HermesColor.separator)
                            .frame(height: 10)
                            .scaleEffect(x: index == lines - 1 && lines > 1 ? 0.6 : 1, anchor: .leading)
                    }
                }
                .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                .padding(.vertical, HermesMetrics.bubbleVerticalPadding)
                .containerRelativeFrame(.horizontal) { total, _ in total * width }
                .background(
                    HermesColor.incomingBubble.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
                )
                if leading { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12)
        }
    }

    /// Fades in the characters that just arrived at the end of streaming text (plan Q47). Older text stays still.
    struct TailFadeRenderer: TextRenderer {
        var tail: Int
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            let slices = layout.flatMap { $0 }.flatMap { $0 }
            let total = slices.count
            for (index, slice) in slices.enumerated() {
                var copy = context
                let fromEnd = total - 1 - index
                if fromEnd < tail {
                    // Oldest new characters appear first, so the reveal runs left to right.
                    let delay = 1 - Double(fromEnd) / Double(max(tail, 1))
                    copy.opacity = min(1, max(0, progress * 2 - (1 - delay)))
                }
                copy.draw(slice)
            }
        }
    }

    /// Applies ``TailFadeRenderer`` to a paragraph while it streams. Reduce Motion gets plain text.
    struct StreamingFade: ViewModifier {
        let text: String
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride
        @State private var tail = 0
        @State private var previousCount = 0

        func body(content: Content) -> some View {
            if HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride) {
                content
            } else {
                content
                    .keyframeAnimator(initialValue: 0.0, trigger: text) { view, progress in
                        view.textRenderer(TailFadeRenderer(tail: tail, progress: progress))
                    } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 0.3)
                    }
                    .onChange(of: text, initial: true) { _, new in
                        let count = new.count
                        tail = min(40, max(0, count - previousCount))
                        previousCount = count
                    }
            }
        }
    }
#endif
