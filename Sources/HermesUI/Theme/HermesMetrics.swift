#if canImport(UIKit)
    import SwiftUI

    /// Spacing, radii and sizes shared by all components.
    ///
    /// Besides `bannerRadius`, `cardRadius` (18) and `innerRadius` (12) are the only other corner radii.
    public enum HermesMetrics {
        /// Apple's minimum tap target.
        public static let minTapTarget: CGFloat = 44
        public static let bubbleRadius: CGFloat = 20
        public static let innerRadius: CGFloat = 12
        /// Banners, the composer field and floating bars.
        public static let bannerRadius: CGFloat = 22
        public static let cardRadius: CGFloat = 18
        public static let bubbleSpacing: CGFloat = 8
        public static let bubbleHorizontalPadding: CGFloat = 14
        public static let bubbleVerticalPadding: CGFloat = 9
        /// Space kept free on the far side of a bubble, so bubbles never span the full width.
        public static let bubbleSideInset: CGFloat = 56
    }
#endif
