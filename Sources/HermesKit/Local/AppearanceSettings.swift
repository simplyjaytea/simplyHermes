import Foundation

/// Selectable appearance presets for simplyHermes (plan WP-20 / design direction v2).
///
/// System preserves the existing native light/dark look with #0068D9 blue accent.
/// Dark gives graphite surfaces with light text and blue controls.
/// Blue gives rich navy surfaces with bright blue accents.
/// White provides light neutral surfaces with dark text and blue controls.
public enum AppearancePreset: String, CaseIterable, Codable, Sendable {
    case system
    case dark
    case blue
    case white

    /// Machine identifier.
    public var id: String { rawValue }

    /// Localized display name.
    public var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .blue: "Blue"
        case .white: "White"
        }
    }

    /// Descriptive summary shown in settings.
    public var subtitle: String {
        switch self {
        case .system: "Follows iOS light and dark mode with standard blue accent"
        case .dark: "Graphite dark theme with light text and blue controls"
        case .blue: "Navy surfaces with blue bubbles and controls"
        case .white: "Light neutral surfaces with dark text and blue controls"
        }
    }

    /// Recovers safely from unknown or empty raw values.
    public static func fallback(for rawValue: String?) -> AppearancePreset {
        guard let rawValue, let preset = AppearancePreset(rawValue: rawValue) else {
            return .system
        }
        return preset
    }
}

/// The device-only persistent preference for appearance presets.
///
/// Kept in `UserDefaults` so the Settings screen (`@AppStorage(AppearanceSettings.key)`)
/// and app root observe and update the same value immediately without writing to server profiles.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe on Apple platforms.
public struct AppearanceSettings: @unchecked Sendable {
    /// `UserDefaults` key for the appearance preset.
    public static let key = "appearancePreset"

    private let defaults: UserDefaults

    /// Reads and writes the preset in `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The selected appearance preset. Unset or unknown values safely fall back to `.system`.
    public var preset: AppearancePreset {
        get {
            let raw = defaults.string(forKey: Self.key)
            return AppearancePreset.fallback(for: raw)
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }

    /// Resets the preference to `.system`.
    public func reset() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Resets appearance settings when requested by launch options (e.g. -HermesResetAppearance YES).
    public static func applyLaunchReset(resetAppearance: Bool, defaults: UserDefaults = .standard) {
        if resetAppearance {
            AppearanceSettings(defaults: defaults).reset()
        }
    }
}

/// A color representation in linear sRGB for contrast verification and palette definition in pure Swift.
public struct RGBColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red / 255.0, 0.0), 1.0)
        self.green = min(max(green / 255.0, 0.0), 1.0)
        self.blue = min(max(blue / 255.0, 0.0), 1.0)
    }

    public init(hex: Int) {
        let redComponent = Double((hex >> 16) & 0xFF)
        let greenComponent = Double((hex >> 8) & 0xFF)
        let blueComponent = Double(hex & 0xFF)
        self.init(red: redComponent, green: greenComponent, blue: blueComponent)
    }

    /// Relative luminance in the sRGB color space according to WCAG 2.1 specifications.
    public var relativeLuminance: Double {
        func channelLuminance(_ val: Double) -> Double {
            if val <= 0.04045 {
                return val / 12.92
            } else {
                return pow((val + 0.055) / 1.055, 2.4)
            }
        }
        let rLum = channelLuminance(red)
        let gLum = channelLuminance(green)
        let bLum = channelLuminance(blue)
        return 0.2126 * rLum + 0.7152 * gLum + 0.0722 * bLum
    }

    /// Calculates the contrast ratio between this color and another color (range 1.0 to 21.0).
    public func contrastRatio(with other: RGBColor) -> Double {
        let lum1 = self.relativeLuminance
        let lum2 = other.relativeLuminance
        let lighter = max(lum1, lum2)
        let darker = min(lum1, lum2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// The authoritative pure-Swift definition of color tokens for each appearance preset.
public struct PresetPaletteDefinition: Equatable, Sendable {
    public let preset: AppearancePreset
    public let background: RGBColor
    public let groupedBackground: RGBColor
    public let card: RGBColor
    public let fill: RGBColor
    public let separator: RGBColor
    public let accent: RGBColor
    public let onAccent: RGBColor
    public let outgoingBubble: RGBColor
    public let incomingBubble: RGBColor
    public let primaryText: RGBColor
    public let secondaryText: RGBColor
    public let codeBackground: RGBColor
    public let codeText: RGBColor
    public let codeKeyword: RGBColor
    public let codeString: RGBColor
    public let codeComment: RGBColor
    public let codeNumber: RGBColor
    public let statusConnected: RGBColor
    public let statusWarning: RGBColor
    public let statusOffline: RGBColor
    public let statusOnlineInk: RGBColor
    public let statusLocalInk: RGBColor
    public let statusWarningInk: RGBColor
    public let statusProblemInk: RGBColor
    public let destructive: RGBColor
    public let onDestructive: RGBColor
    public let errorText: RGBColor
    public let errorBackground: RGBColor

    /// Authoritative mapping from an `AppearancePreset` to its color definition,
    /// supporting dynamic light/dark and accessibility contrast traits.
    public static func definition(
        for preset: AppearancePreset,
        isDark: Bool = false,
        highContrast: Bool = false
    ) -> PresetPaletteDefinition {
        switch preset {
        case .system:
            return systemDefinition(isDark: isDark, highContrast: highContrast)
        case .dark:
            return darkDefinition(highContrast: highContrast)
        case .blue:
            return blueDefinition(highContrast: highContrast)
        case .white:
            return whiteDefinition(highContrast: highContrast)
        }
    }

    private static func systemDefinition(isDark: Bool, highContrast: Bool) -> PresetPaletteDefinition {
        if isDark {
            return PresetPaletteDefinition(
                preset: .system,
                background: RGBColor(hex: 0x000000),
                groupedBackground: RGBColor(hex: 0x000000),
                card: RGBColor(hex: 0x1C1C1E),
                fill: RGBColor(hex: 0x2C2C2E),
                separator: RGBColor(hex: 0x38383A),
                accent: RGBColor(hex: 0x0068D9),
                onAccent: RGBColor(hex: 0xFFFFFF),
                outgoingBubble: RGBColor(hex: 0x0068D9),
                incomingBubble: RGBColor(hex: 0x2C2C2E),
                primaryText: RGBColor(hex: 0xFFFFFF),
                secondaryText: highContrast ? RGBColor(hex: 0xEBEBF5) : RGBColor(hex: 0xA0A0A5),
                codeBackground: RGBColor(hex: 0x1C1C1E),
                codeText: RGBColor(hex: 0xF2F2F7),
                codeKeyword: highContrast ? RGBColor(hex: 0xE9D5FF) : RGBColor(hex: 0xC084FC),
                codeString: highContrast ? RGBColor(hex: 0xBBF7D0) : RGBColor(hex: 0x4ADE80),
                codeComment: highContrast ? RGBColor(hex: 0xCBD5E1) : RGBColor(hex: 0x94A3B8),
                codeNumber: highContrast ? RGBColor(hex: 0xBAE6FD) : RGBColor(hex: 0x38BDF8),
                statusConnected: RGBColor(hex: 0x30D158),
                statusWarning: RGBColor(hex: 0xFF9F0A),
                statusOffline: RGBColor(hex: 0x8E8E93),
                statusOnlineInk: highContrast ? RGBColor(hex: 0x86EFAC) : RGBColor(hex: 0x30D158),
                statusLocalInk: highContrast ? RGBColor(hex: 0xDDD6FE) : RGBColor(hex: 0xC4B5FD),
                statusWarningInk: highContrast ? RGBColor(hex: 0xFCD34D) : RGBColor(hex: 0xFF9F0A),
                statusProblemInk: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
                destructive: RGBColor(hex: 0xDC2626),
                onDestructive: RGBColor(hex: 0xFFFFFF),
                errorText: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
                errorBackground: highContrast ? RGBColor(hex: 0x221316) : RGBColor(hex: 0x2B191D)
            )
        } else {
            return PresetPaletteDefinition(
                preset: .system,
                background: RGBColor(hex: 0xFFFFFF),
                groupedBackground: RGBColor(hex: 0xF2F2F7),
                card: RGBColor(hex: 0xFFFFFF),
                fill: RGBColor(hex: 0xE5E5EA),
                separator: RGBColor(hex: 0xC6C6C8),
                accent: RGBColor(hex: 0x0068D9),
                onAccent: RGBColor(hex: 0xFFFFFF),
                outgoingBubble: RGBColor(hex: 0x0068D9),
                incomingBubble: RGBColor(hex: 0xE5E5EA),
                primaryText: RGBColor(hex: 0x000000),
                secondaryText: highContrast ? RGBColor(hex: 0x3C3C43) : RGBColor(hex: 0x5C5C60),
                codeBackground: RGBColor(hex: 0xF2F2F7),
                codeText: RGBColor(hex: 0x000000),
                codeKeyword: highContrast ? RGBColor(hex: 0x581C87) : RGBColor(hex: 0x7E22CE),
                codeString: highContrast ? RGBColor(hex: 0x991B1B) : RGBColor(hex: 0xB91C1C),
                codeComment: highContrast ? RGBColor(hex: 0x3C3C43) : RGBColor(hex: 0x5C5C60),
                codeNumber: highContrast ? RGBColor(hex: 0x115E59) : RGBColor(hex: 0x0F766E),
                statusConnected: RGBColor(hex: 0x34C759),
                statusWarning: RGBColor(hex: 0xFF9500),
                statusOffline: RGBColor(hex: 0x8E8E93),
                statusOnlineInk: RGBColor(hex: 0x15803D),
                statusLocalInk: RGBColor(hex: 0x6D28D9),
                statusWarningInk: RGBColor(hex: 0xB45309),
                statusProblemInk: RGBColor(hex: 0xB91C1C),
                destructive: RGBColor(hex: 0xDC2626),
                onDestructive: RGBColor(hex: 0xFFFFFF),
                errorText: highContrast ? RGBColor(hex: 0x991B1B) : RGBColor(hex: 0xB91C1C),
                errorBackground: highContrast ? RGBColor(hex: 0xFFF1F1) : RGBColor(hex: 0xFEF2F2)
            )
        }
    }

    private static func darkDefinition(highContrast: Bool) -> PresetPaletteDefinition {
        // Dark graphite preset with light text and blue controls
        PresetPaletteDefinition(
            preset: .dark,
            background: RGBColor(hex: 0x18191B),
            groupedBackground: RGBColor(hex: 0x121315),
            card: RGBColor(hex: 0x242528),
            fill: RGBColor(hex: 0x2F3136),
            separator: RGBColor(hex: 0x383A40),
            accent: RGBColor(hex: 0x0068D9),
            onAccent: RGBColor(hex: 0xFFFFFF),
            outgoingBubble: RGBColor(hex: 0x0068D9),
            incomingBubble: RGBColor(hex: 0x2C2D31),
            primaryText: RGBColor(hex: 0xF2F2F7),
            secondaryText: highContrast ? RGBColor(hex: 0xEBEBF5) : RGBColor(hex: 0xA0A0A5),
            codeBackground: RGBColor(hex: 0x1E1F22),
            codeText: RGBColor(hex: 0xF2F2F7),
            codeKeyword: highContrast ? RGBColor(hex: 0xE9D5FF) : RGBColor(hex: 0xC084FC),
            codeString: highContrast ? RGBColor(hex: 0xBBF7D0) : RGBColor(hex: 0x4ADE80),
            codeComment: highContrast ? RGBColor(hex: 0xCBD5E1) : RGBColor(hex: 0x94A3B8),
            codeNumber: highContrast ? RGBColor(hex: 0xBAE6FD) : RGBColor(hex: 0x38BDF8),
            statusConnected: RGBColor(hex: 0x30D158),
            statusWarning: RGBColor(hex: 0xFF9F0A),
            statusOffline: RGBColor(hex: 0x8E8E93),
            statusOnlineInk: highContrast ? RGBColor(hex: 0x86EFAC) : RGBColor(hex: 0x30D158),
            statusLocalInk: highContrast ? RGBColor(hex: 0xDDD6FE) : RGBColor(hex: 0xC4B5FD),
            statusWarningInk: highContrast ? RGBColor(hex: 0xFCD34D) : RGBColor(hex: 0xFF9F0A),
            statusProblemInk: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
            destructive: RGBColor(hex: 0xDC2626),
            onDestructive: RGBColor(hex: 0xFFFFFF),
            errorText: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
            errorBackground: highContrast ? RGBColor(hex: 0x221316) : RGBColor(hex: 0x2B191D)
        )
    }

    private static func blueDefinition(highContrast: Bool) -> PresetPaletteDefinition {
        // Blue navy preset: deep navy surfaces with blue accents
        PresetPaletteDefinition(
            preset: .blue,
            background: RGBColor(hex: 0x0F172A),
            groupedBackground: RGBColor(hex: 0x0B1120),
            card: RGBColor(hex: 0x162038),
            fill: RGBColor(hex: 0x1E2E4A),
            separator: RGBColor(hex: 0x2A3F66),
            accent: RGBColor(hex: 0x0068D9),
            onAccent: RGBColor(hex: 0xFFFFFF),
            outgoingBubble: RGBColor(hex: 0x0068D9),
            incomingBubble: RGBColor(hex: 0x1E2B45),
            primaryText: RGBColor(hex: 0xF0F6FC),
            secondaryText: highContrast ? RGBColor(hex: 0xC8DBF8) : RGBColor(hex: 0x96AFD2),
            codeBackground: RGBColor(hex: 0x0A1020),
            codeText: RGBColor(hex: 0xE0F2FE),
            codeKeyword: highContrast ? RGBColor(hex: 0xE9D5FF) : RGBColor(hex: 0xC084FC),
            codeString: highContrast ? RGBColor(hex: 0xBBF7D0) : RGBColor(hex: 0x4ADE80),
            codeComment: highContrast ? RGBColor(hex: 0xCBD5E1) : RGBColor(hex: 0x94A3B8),
            codeNumber: highContrast ? RGBColor(hex: 0xBAE6FD) : RGBColor(hex: 0x38BDF8),
            statusConnected: RGBColor(hex: 0x38BDF8),
            statusWarning: RGBColor(hex: 0xFBBF24),
            statusOffline: RGBColor(hex: 0x64748B),
            statusOnlineInk: highContrast ? RGBColor(hex: 0x86EFAC) : RGBColor(hex: 0x38BDF8),
            statusLocalInk: highContrast ? RGBColor(hex: 0xDDD6FE) : RGBColor(hex: 0xC4B5FD),
            statusWarningInk: highContrast ? RGBColor(hex: 0xFCD34D) : RGBColor(hex: 0xFBBF24),
            statusProblemInk: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
            destructive: RGBColor(hex: 0xDC2626),
            onDestructive: RGBColor(hex: 0xFFFFFF),
            errorText: highContrast ? RGBColor(hex: 0xFCA5A5) : RGBColor(hex: 0xF87171),
            errorBackground: highContrast ? RGBColor(hex: 0x1C1220) : RGBColor(hex: 0x241828)
        )
    }

    private static func whiteDefinition(highContrast: Bool) -> PresetPaletteDefinition {
        // White light neutral preset: light neutral surfaces, dark text, blue accent
        PresetPaletteDefinition(
            preset: .white,
            background: RGBColor(hex: 0xFFFFFF),
            groupedBackground: RGBColor(hex: 0xF4F4F6),
            card: RGBColor(hex: 0xFFFFFF),
            fill: RGBColor(hex: 0xEAEAEE),
            separator: RGBColor(hex: 0xD1D1D6),
            accent: RGBColor(hex: 0x0068D9),
            onAccent: RGBColor(hex: 0xFFFFFF),
            outgoingBubble: RGBColor(hex: 0x0068D9),
            incomingBubble: RGBColor(hex: 0xEDEDF0),
            primaryText: RGBColor(hex: 0x111827),
            secondaryText: highContrast ? RGBColor(hex: 0x3C3C43) : RGBColor(hex: 0x646973),
            codeBackground: RGBColor(hex: 0xF1F3F5),
            codeText: RGBColor(hex: 0x111827),
            codeKeyword: highContrast ? RGBColor(hex: 0x581C87) : RGBColor(hex: 0x7E22CE),
            codeString: highContrast ? RGBColor(hex: 0x991B1B) : RGBColor(hex: 0xB91C1C),
            codeComment: highContrast ? RGBColor(hex: 0x3C3C43) : RGBColor(hex: 0x646973),
            codeNumber: highContrast ? RGBColor(hex: 0x115E59) : RGBColor(hex: 0x0F766E),
            statusConnected: RGBColor(hex: 0x16A34A),
            statusWarning: RGBColor(hex: 0xD97706),
            statusOffline: RGBColor(hex: 0x6B7280),
            statusOnlineInk: RGBColor(hex: 0x15803D),
            statusLocalInk: RGBColor(hex: 0x6D28D9),
            statusWarningInk: RGBColor(hex: 0xB45309),
            statusProblemInk: RGBColor(hex: 0xB91C1C),
            destructive: RGBColor(hex: 0xDC2626),
            onDestructive: RGBColor(hex: 0xFFFFFF),
            errorText: highContrast ? RGBColor(hex: 0x991B1B) : RGBColor(hex: 0xB91C1C),
            errorBackground: highContrast ? RGBColor(hex: 0xFFF1F1) : RGBColor(hex: 0xFEF2F2)
        )
    }

    /// Evaluates standard contrast ratios against WCAG 2.1 requirements.
    public var contrastChecks: [String: Double] {
        [
            "primaryOnBackground": primaryText.contrastRatio(with: background),
            "primaryOnIncomingBubble": primaryText.contrastRatio(with: incomingBubble),
            "statusOnlineInkOnBackground": statusOnlineInk.contrastRatio(with: background),
            "statusLocalInkOnBackground": statusLocalInk.contrastRatio(with: background),
            "statusWarningInkOnBackground": statusWarningInk.contrastRatio(with: background),
            "statusProblemInkOnBackground": statusProblemInk.contrastRatio(with: background),
            "secondaryOnBackground": secondaryText.contrastRatio(with: background),
            "secondaryOnIncomingBubble": secondaryText.contrastRatio(with: incomingBubble),
            "onAccentOnAccent": onAccent.contrastRatio(with: accent),
            "onAccentOnOutgoingBubble": onAccent.contrastRatio(with: outgoingBubble),
            "codeTextOnCodeBackground": codeText.contrastRatio(with: codeBackground),
            "codeKeywordOnCodeBackground": codeKeyword.contrastRatio(with: codeBackground),
            "codeStringOnCodeBackground": codeString.contrastRatio(with: codeBackground),
            "codeCommentOnCodeBackground": codeComment.contrastRatio(with: codeBackground),
            "codeNumberOnCodeBackground": codeNumber.contrastRatio(with: codeBackground),
            "onAccentOnDestructive": onDestructive.contrastRatio(with: destructive),
            "onDestructiveOnDestructive": onDestructive.contrastRatio(with: destructive),
            "errorTextOnBackground": errorText.contrastRatio(with: background),
            "errorTextOnErrorBackground": errorText.contrastRatio(with: errorBackground),
            "secondaryTextOnErrorBackground": secondaryText.contrastRatio(with: errorBackground),
        ]
    }
}
