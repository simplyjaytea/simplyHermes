#if canImport(UIKit)
    import SwiftUI

    /// Text styles. SF Pro through Dynamic Type text styles, SF Mono for commands and tool output.
    /// Every style scales with Dynamic Type, which also replaces Desktop's zoom (plan WP-71).
    public enum HermesFont {
        public static let bubble = Font.body
        public static let body = Font.body
        public static let headline = Font.headline
        public static let subheadline = Font.subheadline
        public static let footnote = Font.footnote
        public static let caption = Font.caption
        /// Widget footers such as "Updated 5 min ago".
        public static let caption2 = Font.caption2
        /// Commands, paths and tool output.
        public static let code = Font.system(.footnote, design: .monospaced)
        /// Secondary lines inside tool output, such as the command echo.
        public static let codeSmall = Font.system(.caption, design: .monospaced)
        /// Large title for the tent-posture glance view.
        public static let glanceTitle = Font.title.bold()
    }
#endif
