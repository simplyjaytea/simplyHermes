#if canImport(UIKit)
    import SwiftTerm
    import UIKit

    /// Colors for the terminal in each appearance (plan Q42: the terminal follows the system). The light palette is
    /// darker than the usual one, so CLI colors keep their contrast on white. Each ANSI color is tuned to at least
    /// about 4.5:1 against the light background.
    enum TerminalPalette {
        private struct Theme {
            let background: UInt32
            let foreground: UInt32
            /// Eight normal colors, then eight bright ones: black, red, green, yellow, blue, magenta, cyan, white.
            let ansi: [UInt32]
        }

        private static let dark = Theme(
            background: 0x101012,
            foreground: 0xE6E6EA,
            ansi: [
                0x2A2A2E, 0xFF6B6B, 0x7BD88F, 0xF3D675, 0x7AA2F7, 0xC792EA, 0x5FD4E0, 0xD4D4D8,
                0x6B6B73, 0xFF8A8A, 0x9BE8AA, 0xFFE593, 0x9DBBFF, 0xDDB0F5, 0x8BE6F0, 0xFFFFFF,
            ])

        private static let light = Theme(
            background: 0xFBFBFD,
            foreground: 0x1D1D1F,
            ansi: [
                0x1D1D1F, 0xB42318, 0x17703A, 0x8A5A00, 0x1D4ED8, 0x8A2BA0, 0x0E7490, 0x6B6B70,
                0x5E5E63, 0xC2362B, 0x1F8747, 0x9A6B00, 0x2563EB, 0xA23BB8, 0x0F7C92, 0x3A3A3F,
            ])

        /// Applies the palette for the current appearance, and a monospaced font sized for a phone.
        @MainActor
        static func apply(to view: TerminalView, dark isDark: Bool) {
            let theme = isDark ? dark : light
            view.installColors(theme.ansi.map(terminalColor))
            view.nativeBackgroundColor = uiColor(theme.background)
            view.nativeForegroundColor = uiColor(theme.foreground)
            view.caretColor = uiColor(theme.foreground)
            view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }

        private static func terminalColor(_ value: UInt32) -> SwiftTerm.Color {
            SwiftTerm.Color(
                red8: UInt16((value >> 16) & 0xFF),
                green8: UInt16((value >> 8) & 0xFF),
                blue8: UInt16(value & 0xFF))
        }

        private static func uiColor(_ value: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
        }
    }
#endif
