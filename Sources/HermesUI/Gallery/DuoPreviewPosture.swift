#if canImport(UIKit)
    import SwiftUI

    /// iPhone Duo screen sizes for previews and snapshot tests.
    /// These are estimates (pixels ÷ 3) until WP-02 measures the real point sizes on the Duo simulator.
    public enum DuoPreviewPosture: String, CaseIterable, Sendable {
        /// Outer 5.4" display, folded.
        case outer
        /// Inner 7.6" display, unfolded, portrait.
        case innerPortrait
        /// Inner display, unfolded, landscape.
        case innerLandscape
        /// Inner display in half-fold (laptop) posture: one half of the landscape screen.
        case halfFold

        public var size: CGSize {
            switch self {
            case .outer: CGSize(width: 466, height: 678)
            case .innerPortrait: CGSize(width: 626, height: 890)
            case .innerLandscape: CGSize(width: 890, height: 626)
            case .halfFold: CGSize(width: 890, height: 313)
            }
        }
    }
#endif
