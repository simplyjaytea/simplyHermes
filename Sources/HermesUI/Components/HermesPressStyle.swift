#if canImport(UIKit)
    import SwiftUI

    /// Press feedback for a button that draws its own look: chips, pills, icon buttons and rows. The label shrinks and
    /// dims while it is held, so the user knows the touch landed. Use it where `.buttonStyle(.plain)` would otherwise
    /// give no feedback. With Reduce Motion on, the label only dims.
    ///
    /// It plays no haptic. The style sits on every row of long lists. With one feedback generator for each button the
    /// UI tests ran two to seven times slower (PR #159, run 2), and the haptic was the suspected cause.
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
