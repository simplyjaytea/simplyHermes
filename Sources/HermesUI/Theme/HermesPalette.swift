#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// Authoritative palette providing SwiftUI colors and scheme settings for the active appearance preset.
    ///
    /// Keeps one authoritative preference + palette mapping across the entire app without
    /// mutable global caches or duplicate chat renderers.
    public struct HermesPalette: Sendable, Equatable {
        public let preset: AppearancePreset
        public let accent: Color
        public let onAccent: Color
        public let background: Color
        public let groupedBackground: Color
        public let card: Color
        public let fill: Color
        public let separator: Color
        public let outgoingBubble: Color
        public let incomingBubble: Color
        public let primaryText: Color
        public let secondaryText: Color
        public let codeBackground: Color
        public let codeText: Color
        public let codeKeyword: Color
        public let codeString: Color
        public let codeComment: Color
        public let codeNumber: Color
        public let statusConnected: Color
        public let statusWarning: Color
        public let statusOffline: Color
        public let statusOnlineInk: Color
        public let statusLocalInk: Color
        public let statusWarningInk: Color
        public let statusProblemInk: Color
        public let destructive: Color
        public let onDestructive: Color
        public let errorText: Color
        public let errorBackground: Color
        public let colorScheme: ColorScheme?

        /// Creates a dynamic `UIColor` for a given preset that adapts to trait collection changes (light/dark and increase contrast).
        public static func dynamicUIColor(
            for preset: AppearancePreset,
            _ keyPath: KeyPath<PresetPaletteDefinition, RGBColor>
        ) -> UIColor {
            UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let isHighContrast = traits.accessibilityContrast == .high
                let definition = PresetPaletteDefinition.definition(
                    for: preset,
                    isDark: isDark,
                    highContrast: isHighContrast
                )
                let rgbColor = definition[keyPath: keyPath]
                return UIColor(red: rgbColor.red, green: rgbColor.green, blue: rgbColor.blue, alpha: 1.0)
            }
        }

        /// Creates a dynamic SwiftUI `Color` for a given preset that adapts to trait collection changes.
        public static func dynamicColor(
            for preset: AppearancePreset,
            _ keyPath: KeyPath<PresetPaletteDefinition, RGBColor>
        ) -> Color {
            Color(uiColor: dynamicUIColor(for: preset, keyPath))
        }

        /// Creates a dynamic `UIColor` for `.system` that adapts to trait collection changes (light/dark and increase contrast).
        public static func dynamicSystemUIColor(
            _ keyPath: KeyPath<PresetPaletteDefinition, RGBColor>
        ) -> UIColor {
            dynamicUIColor(for: .system, keyPath)
        }

        private static func dynamicSystemColor(
            _ keyPath: KeyPath<PresetPaletteDefinition, RGBColor>
        ) -> Color {
            dynamicColor(for: .system, keyPath)
        }

        /// Resolves the pure palette definition for the given preset and specific UIKit traits.
        public static func resolvedDefinition(
            for preset: AppearancePreset,
            traits: UITraitCollection = UITraitCollection.current
        ) -> PresetPaletteDefinition {
            let isDark = traits.userInterfaceStyle == .dark
            let isHighContrast = traits.accessibilityContrast == .high
            return PresetPaletteDefinition.definition(for: preset, isDark: isDark, highContrast: isHighContrast)
        }

        /// Resolves a fixed HermesPalette under explicit UIKit traits (useful for snapshots, testing, and static resolution).
        public static func palette(
            for preset: AppearancePreset,
            traits: UITraitCollection
        ) -> HermesPalette {
            let def = resolvedDefinition(for: preset, traits: traits)
            let scheme: ColorScheme? = {
                switch preset {
                case .system:
                    return traits.userInterfaceStyle == .dark ? .dark : .light
                case .dark, .blue:
                    return .dark
                case .white:
                    return .light
                }
            }()
            return HermesPalette(
                preset: preset,
                accent: Color(red: def.accent.red, green: def.accent.green, blue: def.accent.blue),
                onAccent: Color(red: def.onAccent.red, green: def.onAccent.green, blue: def.onAccent.blue),
                background: Color(red: def.background.red, green: def.background.green, blue: def.background.blue),
                groupedBackground: Color(
                    red: def.groupedBackground.red, green: def.groupedBackground.green, blue: def.groupedBackground.blue
                ),
                card: Color(red: def.card.red, green: def.card.green, blue: def.card.blue),
                fill: Color(red: def.fill.red, green: def.fill.green, blue: def.fill.blue),
                separator: Color(red: def.separator.red, green: def.separator.green, blue: def.separator.blue),
                outgoingBubble: Color(
                    red: def.outgoingBubble.red, green: def.outgoingBubble.green, blue: def.outgoingBubble.blue
                ),
                incomingBubble: Color(
                    red: def.incomingBubble.red, green: def.incomingBubble.green, blue: def.incomingBubble.blue
                ),
                primaryText: Color(red: def.primaryText.red, green: def.primaryText.green, blue: def.primaryText.blue),
                secondaryText: Color(
                    red: def.secondaryText.red, green: def.secondaryText.green, blue: def.secondaryText.blue
                ),
                codeBackground: Color(
                    red: def.codeBackground.red, green: def.codeBackground.green, blue: def.codeBackground.blue
                ),
                codeText: Color(red: def.codeText.red, green: def.codeText.green, blue: def.codeText.blue),
                codeKeyword: Color(
                    red: def.codeKeyword.red, green: def.codeKeyword.green, blue: def.codeKeyword.blue
                ),
                codeString: Color(red: def.codeString.red, green: def.codeString.green, blue: def.codeString.blue),
                codeComment: Color(
                    red: def.codeComment.red, green: def.codeComment.green, blue: def.codeComment.blue
                ),
                codeNumber: Color(red: def.codeNumber.red, green: def.codeNumber.green, blue: def.codeNumber.blue),
                statusConnected: Color(
                    red: def.statusConnected.red, green: def.statusConnected.green, blue: def.statusConnected.blue
                ),
                statusWarning: Color(
                    red: def.statusWarning.red, green: def.statusWarning.green, blue: def.statusWarning.blue
                ),
                statusOffline: Color(
                    red: def.statusOffline.red, green: def.statusOffline.green, blue: def.statusOffline.blue
                ),
                statusOnlineInk: Color(
                    red: def.statusOnlineInk.red, green: def.statusOnlineInk.green, blue: def.statusOnlineInk.blue
                ),
                statusLocalInk: Color(
                    red: def.statusLocalInk.red, green: def.statusLocalInk.green, blue: def.statusLocalInk.blue
                ),
                statusWarningInk: Color(
                    red: def.statusWarningInk.red, green: def.statusWarningInk.green, blue: def.statusWarningInk.blue
                ),
                statusProblemInk: Color(
                    red: def.statusProblemInk.red, green: def.statusProblemInk.green, blue: def.statusProblemInk.blue
                ),
                destructive: Color(
                    red: def.destructive.red, green: def.destructive.green, blue: def.destructive.blue
                ),
                onDestructive: Color(
                    red: def.onDestructive.red, green: def.onDestructive.green, blue: def.onDestructive.blue
                ),
                errorText: Color(
                    red: def.errorText.red, green: def.errorText.green, blue: def.errorText.blue
                ),
                errorBackground: Color(
                    red: def.errorBackground.red, green: def.errorBackground.green, blue: def.errorBackground.blue
                ),
                colorScheme: scheme
            )
        }

        /// Single authoritative mapping from `AppearancePreset` to `HermesPalette`.
        public static func palette(for preset: AppearancePreset) -> HermesPalette {
            switch preset {
            case .system:
                return HermesPalette(
                    preset: .system,
                    accent: HermesColor.accent,
                    onAccent: HermesColor.onAccent,
                    background: Color(uiColor: .systemBackground),
                    groupedBackground: Color(uiColor: .systemGroupedBackground),
                    card: Color(uiColor: .secondarySystemGroupedBackground),
                    fill: Color(uiColor: .tertiarySystemFill),
                    separator: Color(uiColor: .separator),
                    outgoingBubble: HermesColor.outgoingBubble,
                    incomingBubble: Color(uiColor: .systemGray5),
                    primaryText: Color.primary,
                    secondaryText: dynamicSystemColor(\.secondaryText),
                    codeBackground: Color(uiColor: .tertiarySystemFill),
                    codeText: Color.primary,
                    codeKeyword: dynamicSystemColor(\.codeKeyword),
                    codeString: dynamicSystemColor(\.codeString),
                    codeComment: dynamicSystemColor(\.codeComment),
                    codeNumber: dynamicSystemColor(\.codeNumber),
                    statusConnected: Color(uiColor: .systemGreen),
                    statusWarning: Color(uiColor: .systemOrange),
                    statusOffline: Color(uiColor: .systemGray),
                    statusOnlineInk: dynamicSystemColor(\.statusOnlineInk),
                    statusLocalInk: dynamicSystemColor(\.statusLocalInk),
                    statusWarningInk: dynamicSystemColor(\.statusWarningInk),
                    statusProblemInk: dynamicSystemColor(\.statusProblemInk),
                    destructive: dynamicSystemColor(\.destructive),
                    onDestructive: dynamicSystemColor(\.onDestructive),
                    errorText: dynamicSystemColor(\.errorText),
                    errorBackground: dynamicSystemColor(\.errorBackground),
                    colorScheme: nil
                )
            case .dark, .blue, .white:
                let scheme: ColorScheme? = (preset == .white) ? .light : .dark
                return HermesPalette(
                    preset: preset,
                    accent: HermesColor.accent,
                    onAccent: Color.white,
                    background: dynamicColor(for: preset, \.background),
                    groupedBackground: dynamicColor(for: preset, \.groupedBackground),
                    card: dynamicColor(for: preset, \.card),
                    fill: dynamicColor(for: preset, \.fill),
                    separator: dynamicColor(for: preset, \.separator),
                    outgoingBubble: HermesColor.outgoingBubble,
                    incomingBubble: dynamicColor(for: preset, \.incomingBubble),
                    primaryText: dynamicColor(for: preset, \.primaryText),
                    secondaryText: dynamicColor(for: preset, \.secondaryText),
                    codeBackground: dynamicColor(for: preset, \.codeBackground),
                    codeText: dynamicColor(for: preset, \.codeText),
                    codeKeyword: dynamicColor(for: preset, \.codeKeyword),
                    codeString: dynamicColor(for: preset, \.codeString),
                    codeComment: dynamicColor(for: preset, \.codeComment),
                    codeNumber: dynamicColor(for: preset, \.codeNumber),
                    statusConnected: dynamicColor(for: preset, \.statusConnected),
                    statusWarning: dynamicColor(for: preset, \.statusWarning),
                    statusOffline: dynamicColor(for: preset, \.statusOffline),
                    statusOnlineInk: dynamicColor(for: preset, \.statusOnlineInk),
                    statusLocalInk: dynamicColor(for: preset, \.statusLocalInk),
                    statusWarningInk: dynamicColor(for: preset, \.statusWarningInk),
                    statusProblemInk: dynamicColor(for: preset, \.statusProblemInk),
                    destructive: dynamicColor(for: preset, \.destructive),
                    onDestructive: Color.white,
                    errorText: dynamicColor(for: preset, \.errorText),
                    errorBackground: dynamicColor(for: preset, \.errorBackground),
                    colorScheme: scheme
                )
            }
        }

        public static let system = palette(for: .system)
    }

    private struct HermesPaletteKey: EnvironmentKey {
        static let defaultValue: HermesPalette = .system
    }

    private struct HermesAppearancePresetKey: EnvironmentKey {
        static let defaultValue: AppearancePreset = .system
    }

    extension EnvironmentValues {
        public var hermesPalette: HermesPalette {
            get { self[HermesPaletteKey.self] }
            set { self[HermesPaletteKey.self] = newValue }
        }

        public var hermesAppearancePreset: AppearancePreset {
            get { self[HermesAppearancePresetKey.self] }
            set { self[HermesAppearancePresetKey.self] = newValue }
        }
    }

    extension View {
        /// Applies the authoritative appearance preset to this view hierarchy.
        public func hermesAppearance(_ preset: AppearancePreset) -> some View {
            let palette = HermesPalette.palette(for: preset)
            return
                self
                .environment(\.hermesAppearancePreset, preset)
                .environment(\.hermesPalette, palette)
                .tint(palette.accent)
                .preferredColorScheme(palette.colorScheme)
        }
    }
#endif
