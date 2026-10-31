import Foundation
import HermesKit
import Testing

struct AppearanceSettingsTests {
    private func makeCleanDefaults() -> (UserDefaults, String) {
        let suiteName = "test.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test func defaultPresetIsSystem() {
        let (defaults, suite) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.preset == .system)
    }

    @Test func persistingAndReadingPresets() {
        let (defaults, suite) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppearanceSettings(defaults: defaults)

        for preset in AppearancePreset.allCases {
            settings.preset = preset
            #expect(settings.preset == preset)
            #expect(defaults.string(forKey: AppearanceSettings.key) == preset.rawValue)
        }
    }

    @Test func unknownAndCorruptedValuesFallBackToSystem() {
        let (defaults, suite) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppearanceSettings(defaults: defaults)

        // Unknown string
        defaults.set("neon-magenta", forKey: AppearanceSettings.key)
        #expect(settings.preset == .system)

        // Empty string
        defaults.set("", forKey: AppearanceSettings.key)
        #expect(settings.preset == .system)

        // Integer instead of string
        defaults.set(42, forKey: AppearanceSettings.key)
        #expect(settings.preset == .system)

        // Direct fallback testing
        #expect(AppearancePreset.fallback(for: nil) == .system)
        #expect(AppearancePreset.fallback(for: "invalid") == .system)
        #expect(AppearancePreset.fallback(for: "dark") == .dark)
        #expect(AppearancePreset.fallback(for: "blue") == .blue)
        #expect(AppearancePreset.fallback(for: "white") == .white)
    }

    @Test func resetRestoresSystem() {
        let (defaults, suite) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppearanceSettings(defaults: defaults)
        settings.preset = .blue
        #expect(settings.preset == .blue)

        settings.reset()
        #expect(settings.preset == .system)
        #expect(defaults.object(forKey: AppearanceSettings.key) == nil)
    }

    @Test func presetDescriptionsAndIdentifiersAreValid() {
        for preset in AppearancePreset.allCases {
            #expect(!preset.id.isEmpty)
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.subtitle.isEmpty)
        }
    }

    @Test func wcagContrastRatiosMeetRequirements() {
        for preset in AppearancePreset.allCases {
            // Test both standard and dark variants (especially dynamic .system)
            let variants: [(Bool, Bool)] = [
                (false, false),  // standard light
                (true, false),  // standard dark
                (false, true),  // high contrast light
                (true, true),  // high contrast dark
            ]

            for (isDark, highContrast) in variants {
                let def = PresetPaletteDefinition.definition(for: preset, isDark: isDark, highContrast: highContrast)
                let checks = def.contrastChecks

                // Normal body text on background must meet WCAG AA (>= 4.5:1)
                let primaryOnBg = try! #require(checks["primaryOnBackground"])
                #expect(
                    primaryOnBg >= 4.5,
                    "Failed primaryOnBg for \(preset) (dark: \(isDark), hc: \(highContrast)): \(primaryOnBg)")

                // Normal body text on incoming bubble must meet WCAG AA (>= 4.5:1)
                let primaryOnBubble = try! #require(checks["primaryOnIncomingBubble"])
                #expect(primaryOnBubble >= 4.5, "Failed primaryOnBubble for \(preset): \(primaryOnBubble)")

                // Caption and secondary text must meet WCAG AA (>= 4.5:1)
                let secOnBg = try! #require(checks["secondaryOnBackground"])
                #expect(secOnBg >= 4.5, "Failed secOnBg for \(preset): \(secOnBg)")

                let secOnBubble = try! #require(checks["secondaryOnIncomingBubble"])
                #expect(secOnBubble >= 4.5, "Failed secOnBubble for \(preset): \(secOnBubble)")

                // Button pair 1: Primary button text (onAccent) on accent fill must meet WCAG AA (>= 4.5:1)
                let onAccent = try! #require(checks["onAccentOnAccent"])
                #expect(onAccent >= 4.5, "Failed onAccent for \(preset): \(onAccent)")

                // Button pair 2: Secondary button text (primaryText) on background must meet WCAG AA (>= 4.5:1)
                let secBtnContrast = def.primaryText.contrastRatio(with: def.background)
                #expect(secBtnContrast >= 4.5, "Failed secondary button contrast for \(preset): \(secBtnContrast)")

                // Button pair 3: Tinted button text (primaryText) on fill must meet WCAG AA (>= 4.5:1)
                let tintedBtnContrast = def.primaryText.contrastRatio(with: def.fill)
                #expect(tintedBtnContrast >= 4.5, "Failed tinted button contrast for \(preset): \(tintedBtnContrast)")

                // Button pair 4: Destructive button text (onDestructive) on destructive fill must meet WCAG AA (>= 4.5:1)
                let onDestructive = try! #require(checks["onDestructiveOnDestructive"])
                #expect(onDestructive >= 4.5, "Failed onDestructive for \(preset): \(onDestructive)")

                // Outgoing bubble text (onAccent) on bubble fill must meet WCAG AA (>= 4.5:1)
                let onOutgoing = try! #require(checks["onAccentOnOutgoingBubble"])
                #expect(onOutgoing >= 4.5, "Failed onOutgoing for \(preset): \(onOutgoing)")

                // Code tokens on code background must all meet WCAG AA (>= 4.5:1)
                let codeContrast = try! #require(checks["codeTextOnCodeBackground"])
                #expect(codeContrast >= 4.5, "Failed codeContrast for \(preset): \(codeContrast)")

                let keywordContrast = try! #require(checks["codeKeywordOnCodeBackground"])
                #expect(keywordContrast >= 4.5, "Failed keywordContrast for \(preset): \(keywordContrast)")

                let stringContrast = try! #require(checks["codeStringOnCodeBackground"])
                #expect(stringContrast >= 4.5, "Failed stringContrast for \(preset): \(stringContrast)")

                let commentContrast = try! #require(checks["codeCommentOnCodeBackground"])
                #expect(commentContrast >= 4.5, "Failed commentContrast for \(preset): \(commentContrast)")

                let numberContrast = try! #require(checks["codeNumberOnCodeBackground"])
                #expect(numberContrast >= 4.5, "Failed numberContrast for \(preset): \(numberContrast)")
            }
        }
    }

    @Test func systemPresetAdaptsToTraitsAndHighContrast() {
        let lightDef = PresetPaletteDefinition.definition(for: .system, isDark: false, highContrast: false)
        let darkDef = PresetPaletteDefinition.definition(for: .system, isDark: true, highContrast: false)

        // Dark mode must provide distinct text and syntax colors from light mode
        #expect(lightDef.secondaryText != darkDef.secondaryText)
        #expect(lightDef.codeKeyword != darkDef.codeKeyword)
        #expect(lightDef.codeString != darkDef.codeString)
        #expect(lightDef.codeComment != darkDef.codeComment)
        #expect(lightDef.codeNumber != darkDef.codeNumber)
        #expect(lightDef.primaryText != darkDef.primaryText)
        #expect(lightDef.background != darkDef.background)

        // High contrast mode boosts contrast in both light and dark
        let lightHC = PresetPaletteDefinition.definition(for: .system, isDark: false, highContrast: true)
        let darkHC = PresetPaletteDefinition.definition(for: .system, isDark: true, highContrast: true)

        let lightStandardKeywordContrast = lightDef.codeKeyword.contrastRatio(with: lightDef.codeBackground)
        let lightHCKeywordContrast = lightHC.codeKeyword.contrastRatio(with: lightHC.codeBackground)
        #expect(lightHCKeywordContrast > lightStandardKeywordContrast)

        let darkStandardKeywordContrast = darkDef.codeKeyword.contrastRatio(with: darkDef.codeBackground)
        let darkHCKeywordContrast = darkHC.codeKeyword.contrastRatio(with: darkHC.codeBackground)
        #expect(darkHCKeywordContrast > darkStandardKeywordContrast)

        let lightStandardSecContrast = lightDef.secondaryText.contrastRatio(with: lightDef.background)
        let lightHCSecContrast = lightHC.secondaryText.contrastRatio(with: lightHC.background)
        #expect(lightHCSecContrast > lightStandardSecContrast)

        let darkStandardSecContrast = darkDef.secondaryText.contrastRatio(with: darkDef.background)
        let darkHCSecContrast = darkHC.secondaryText.contrastRatio(with: darkHC.background)
        #expect(darkHCSecContrast > darkStandardSecContrast)
    }

    @Test func rgbColorLuminanceAndContrastMath() {
        let white = RGBColor(hex: 0xFFFFFF)
        let black = RGBColor(hex: 0x000000)

        #expect(white.relativeLuminance > 0.99)
        #expect(black.relativeLuminance < 0.01)

        let blackWhiteContrast = white.contrastRatio(with: black)
        #expect(blackWhiteContrast >= 20.9)

        let sameContrast = white.contrastRatio(with: white)
        #expect(abs(sameContrast - 1.0) < 0.001)

        // System blue #0068D9 on white
        let systemBlue = RGBColor(hex: 0x0068D9)
        let blueContrast = white.contrastRatio(with: systemBlue)
        #expect(blueContrast >= 5.0)
    }
}
