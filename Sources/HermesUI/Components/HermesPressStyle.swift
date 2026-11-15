#if canImport(UIKit)
    import SwiftUI

    /// Press feedback for a button that draws its own look: chips, pills, icon buttons and rows. The label shrinks and
    /// dims while it is held, and a light tap plays when the press starts, so the user knows the touch landed. Use it
    /// where `.buttonStyle(.plain)` would otherwise give no feedback. With Reduce Motion on, the label only dims.
    public struct HermesPressStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .animation(
                    HermesMotion.animation(HermesMotion.press, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
                .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
        }

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }
    }

    extension ButtonStyle where Self == HermesPressStyle {
        /// Press feedback for a button that draws its own look. See ``HermesPressStyle``.
        public static var hermesPress: HermesPressStyle { HermesPressStyle() }
    }
#endif
