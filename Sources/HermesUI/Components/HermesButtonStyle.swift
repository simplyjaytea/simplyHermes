#if canImport(UIKit)
    import SwiftUI

    /// Rounded-rectangle button used inside bubbles, cards and sheets.
    public struct HermesButtonStyle: ButtonStyle {
        public enum Kind: Sendable {
            /// Accent fill, white text (Approve, Save).
            case primary
            /// Background-colored fill, for use on a grey bubble or card (Deny, Cancel).
            case secondary
            /// Light grey fill on the plain background.
            case tinted
            /// Red fill, white text, for actions that cannot be undone.
            case destructive
        }

        private let kind: Kind
        private let fillsWidth: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        public init(_ kind: Kind = .primary, fillsWidth: Bool = true) {
            self.kind = kind
            self.fillsWidth = fillsWidth
        }

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: HermesMetrics.minTapTarget)
                .foregroundStyle(foreground)
                .background(
                    background,
                    in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(
                    HermesMotion.animation(HermesMotion.press, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        private var foreground: Color {
            switch kind {
            case .primary, .destructive: HermesColor.onAccent
            case .secondary, .tinted: HermesColor.primaryText
            }
        }

        private var background: Color {
            switch kind {
            case .primary: HermesColor.accent
            case .secondary: HermesColor.background
            case .tinted: HermesColor.fill
            case .destructive: HermesColor.destructive
            }
        }
    }
#endif
