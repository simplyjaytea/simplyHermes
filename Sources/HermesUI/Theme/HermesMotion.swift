#if canImport(UIKit)
    import SwiftUI

    extension EnvironmentValues {
        /// Forces Reduce Motion on or off for previews and snapshot tests. `nil` follows the system setting.
        @Entry public var hermesReduceMotion: Bool? = nil  // swiftlint:disable:this redundant_optional_initialization
    }

    /// Motion for simplyHermes. Plan Q8 chose rich motion; every animation here has a
    /// Reduce Motion fallback that keeps only short opacity fades.
    public enum HermesMotion {
        /// Buttons, chips, toggles.
        public static let snappy = Animation.spring(duration: 0.3, bounce: 0.2)
        /// A new message bubble arriving.
        public static let bubbleIn = Animation.spring(duration: 0.45, bounce: 0.3)
        /// Layout changes such as fold and unfold, sheets and the preview rail.
        public static let gentle = Animation.spring(duration: 0.5, bounce: 0.1)
        /// Press feedback on buttons.
        public static let press = Animation.spring(duration: 0.2, bounce: 0.4)
        /// The only animation used while Reduce Motion is on.
        public static let reducedFade = Animation.easeInOut(duration: 0.15)

        /// The effective Reduce Motion value: an explicit override wins over the system setting.
        public static func resolveReduceMotion(system: Bool, override: Bool?) -> Bool {
            override ?? system
        }

        /// `animation`, or a short fade when Reduce Motion is on.
        public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reducedFade : animation
        }

        /// How a message bubble enters the transcript.
        @MainActor
        public static func bubbleTransition(isOutgoing: Bool, reduceMotion: Bool) -> AnyTransition {
            if reduceMotion {
                return .opacity
            }
            let anchor: UnitPoint = isOutgoing ? .bottomTrailing : .bottomLeading
            let insertion = AnyTransition.move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.92, anchor: anchor))
            return .asymmetric(insertion: insertion, removal: .opacity)
        }
    }
#endif
