#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// simplyHermes colors. Pure native (plan Q1): every color is an iOS system color,
    /// so light and dark mode (Q10) and Increase Contrast come from the system.
    /// The only custom value is the accent.
    public enum HermesColor {
        /// System blue, darkened from #007AFF to #0068D9 so white text on it reaches 4.5:1.
        /// Chosen by JT on 2026-10-14; the same value in light and dark mode.
        public static let accent = Color(red: 0, green: 104 / 255, blue: 217 / 255)
        /// Text and icons drawn on the accent.
        public static let onAccent = Color.white

        public static let background = Color(uiColor: .systemBackground)
        public static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        public static let card = Color(uiColor: .secondarySystemGroupedBackground)
        public static let fill = Color(uiColor: .tertiarySystemFill)
        public static let separator = Color(uiColor: .separator)

        /// Your messages: accent bubble with white text (chat style A, "Bubbles").
        public static let outgoingBubble = accent
        /// Hermes messages, tool output and approvals: grey bubble.
        public static let incomingBubble = Color(uiColor: .systemGray5)

        public static let primaryText = Color.primary
        public static let secondaryText = Color.secondary

        public static let statusConnected = Color(uiColor: .systemGreen)
        public static let statusWarning = Color(uiColor: .systemOrange)
        public static let statusOffline = Color(uiColor: .systemGray)
        public static let destructive = Color(uiColor: .systemRed)
    }
#endif
