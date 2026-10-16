#if canImport(UIKit)
    import SwiftUI

    /// How the iPhone Duo is folded. WP-02 supplies the real value from the system posture API;
    /// until then it stays `.flat` unless a launch argument or preview sets it.
    public enum DevicePosture: String, CaseIterable, Sendable {
        case flat
        case halfFolded
        case tent
    }

    extension EnvironmentValues {
        /// The current device posture. WP-02 sets it from the system.
        @Entry public var hermesPosture: DevicePosture = .flat
        /// The layout the shell picked, for diagnostics. Nil outside the shell.
        @Entry public var hermesDisplayLayout: DisplayLayout?
    }

    /// The shell layout for the current screen and posture (plan Q3, Q4, Q5, tent glance view).
    public enum DisplayLayout: String, CaseIterable, Sendable {
        /// Outer screen and regular iPhones: chat-first Simple mode with a tab bar.
        case compact
        /// Inner screen, portrait: sidebar and chat.
        case innerPortrait
        /// Inner screen, landscape: sidebar, chat and preview rail.
        case innerLandscape
        /// Half-fold: transcript on top, composer and quick actions below.
        case halfFold
        /// Tent: glance view with large Stop, Deny and Approve.
        case tent

        public static func resolve(
            horizontalSizeClass: UserInterfaceSizeClass?,
            size: CGSize,
            posture: DevicePosture
        ) -> DisplayLayout {
            switch posture {
            case .tent:
                return .tent
            case .halfFolded:
                return .halfFold
            case .flat:
                guard horizontalSizeClass == .regular else { return .compact }
                return size.width > size.height ? .innerLandscape : .innerPortrait
            }
        }
    }
#endif
