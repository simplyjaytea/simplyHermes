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

    @Test func wcagContrastRatiosMeetRequirements() throws {
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
                let primaryOnBg = try #require(checks["primaryOnBackground"])
                #expect(
                    primaryOnBg >= 4.5,
                    "Failed primaryOnBg for \(preset) (dark: \(isDark), hc: \(highContrast)): \(primaryOnBg)")

                // Normal body text on incoming bubble must meet WCAG AA (>= 4.5:1)
                let primaryOnBubble = try #require(checks["primaryOnIncomingBubble"])
                #expect(primaryOnBubble >= 4.5, "Failed primaryOnBubble for \(preset): \(primaryOnBubble)")

                // Caption and secondary text must meet WCAG AA (>= 4.5:1)
                let secOnBg = try #require(checks["secondaryOnBackground"])
                #expect(secOnBg >= 4.5, "Failed secOnBg for \(preset): \(secOnBg)")

                let secOnBubble = try #require(checks["secondaryOnIncomingBubble"])
                #expect(secOnBubble >= 4.5, "Failed secOnBubble for \(preset): \(secOnBubble)")

                // Button pair 1: Primary button text (onAccent) on accent fill must meet WCAG AA (>= 4.5:1)
                let onAccent = try #require(checks["onAccentOnAccent"])
                #expect(onAccent >= 4.5, "Failed onAccent for \(preset): \(onAccent)")

                // Button pair 2: Secondary button text (primaryText) on background must meet WCAG AA (>= 4.5:1)
                let secBtnContrast = def.primaryText.contrastRatio(with: def.background)
                #expect(secBtnContrast >= 4.5, "Failed secondary button contrast for \(preset): \(secBtnContrast)")

                // Button pair 3: Tinted button text (primaryText) on fill must meet WCAG AA (>= 4.5:1)
                let tintedBtnContrast = def.primaryText.contrastRatio(with: def.fill)
                #expect(tintedBtnContrast >= 4.5, "Failed tinted button contrast for \(preset): \(tintedBtnContrast)")

                // Button pair 4: Destructive button text (onDestructive) on destructive fill must meet WCAG AA (>= 4.5:1)
                let onDestructive = try #require(checks["onDestructiveOnDestructive"])
                #expect(onDestructive >= 4.5, "Failed onDestructive for \(preset): \(onDestructive)")

                // Outgoing bubble text (onAccent) on bubble fill must meet WCAG AA (>= 4.5:1)
                let onOutgoing = try #require(checks["onAccentOnOutgoingBubble"])
                #expect(onOutgoing >= 4.5, "Failed onOutgoing for \(preset): \(onOutgoing)")

                // Code tokens on code background must all meet WCAG AA (>= 4.5:1)
                let codeContrast = try #require(checks["codeTextOnCodeBackground"])
                #expect(codeContrast >= 4.5, "Failed codeContrast for \(preset): \(codeContrast)")

                let keywordContrast = try #require(checks["codeKeywordOnCodeBackground"])
                #expect(keywordContrast >= 4.5, "Failed keywordContrast for \(preset): \(keywordContrast)")

                let stringContrast = try #require(checks["codeStringOnCodeBackground"])
                #expect(stringContrast >= 4.5, "Failed stringContrast for \(preset): \(stringContrast)")

                let commentContrast = try #require(checks["codeCommentOnCodeBackground"])
                #expect(commentContrast >= 4.5, "Failed commentContrast for \(preset): \(commentContrast)")

                let numberContrast = try #require(checks["codeNumberOnCodeBackground"])
                #expect(numberContrast >= 4.5, "Failed numberContrast for \(preset): \(numberContrast)")

                // Error text ink on background must meet WCAG AA (>= 4.5:1)
                let errorOnBg = try #require(checks["errorTextOnBackground"])
                #expect(
                    errorOnBg >= 4.5,
                    "Failed errorTextOnBackground for \(preset) (dark: \(isDark), hc: \(highContrast)): \(errorOnBg)"
                )

                // Error text on error background card must meet WCAG AA (>= 4.5:1)
                let errorOnCard = try #require(checks["errorTextOnErrorBackground"])
                #expect(
                    errorOnCard >= 4.5,
                    "Failed errorTextOnErrorBackground for \(preset) (dark: \(isDark), hc: \(highContrast)): \(errorOnCard)"
                )

                // Secondary text on error background card must meet WCAG AA (>= 4.5:1)
                let secOnErrorCard = try #require(checks["secondaryTextOnErrorBackground"])
                #expect(
                    secOnErrorCard >= 4.5,
                    "Failed secondaryTextOnErrorBackground for \(preset) (dark: \(isDark), hc: \(highContrast)): \(secOnErrorCard)"
                )
            }
        }
    }

    @Test func errorTextIsDistinctFromDestructiveButtonFill() {
        // Dark backgrounds (#18191B for dark, #0F172A for blue) demonstrate why destructive button fill
        // (#DC2626) is insufficient for text (< 4.0:1), requiring dedicated semantic errorText (>= 4.5:1).
        for preset in [AppearancePreset.dark, AppearancePreset.blue] {
            let defDark = PresetPaletteDefinition.definition(for: preset, isDark: true, highContrast: false)
            // Dedicated error text ink on dark background meets WCAG AA (>= 4.5:1)
            let errorTextContrast = defDark.errorText.contrastRatio(with: defDark.background)
            #expect(
                errorTextContrast >= 4.5, "errorText contrast on \(preset) should be >= 4.5:1, got \(errorTextContrast)"
            )

            // Destructive button fill #DC2626 on dark background has insufficient contrast for text (< 4.0:1)
            let destructiveFillAsTextContrast = defDark.destructive.contrastRatio(with: defDark.background)
            #expect(
                destructiveFillAsTextContrast < 4.0,
                "destructive button fill on \(preset) background unexpectedly had >= 4.0:1 contrast: \(destructiveFillAsTextContrast)"
            )

            // Destructive button fill is correctly paired with high-contrast white onDestructive (>= 4.5:1)
            let buttonTextContrast = defDark.onDestructive.contrastRatio(with: defDark.destructive)
            #expect(buttonTextContrast >= 4.5)

            // Error text ink must be distinct from destructive button fill in dark presets
            #expect(defDark.errorText != defDark.destructive)
        }

        // Across all presets, errorText meets >= 4.5:1 on background and errorBackground
        for preset in AppearancePreset.allCases {
            let def = PresetPaletteDefinition.definition(for: preset)
            #expect(def.errorText.contrastRatio(with: def.background) >= 4.5)
            #expect(def.errorText.contrastRatio(with: def.errorBackground) >= 4.5)
            #expect(def.secondaryText.contrastRatio(with: def.errorBackground) >= 4.5)
            #expect(def.onDestructive.contrastRatio(with: def.destructive) >= 4.5)
        }
    }

    @Test func systemPresetAdaptsToTraitsAndHighContrast() {
        let lightDef = PresetPaletteDefinition.definition(for: .system, isDark: false, highContrast: false)
        let darkDef = PresetPaletteDefinition.definition(for: .system, isDark: true, highContrast: false)

        // Dark mode must provide distinct text, syntax, and error colors from light mode
        #expect(lightDef.secondaryText != darkDef.secondaryText)
        #expect(lightDef.codeKeyword != darkDef.codeKeyword)
        #expect(lightDef.codeString != darkDef.codeString)
        #expect(lightDef.codeComment != darkDef.codeComment)
        #expect(lightDef.codeNumber != darkDef.codeNumber)
        #expect(lightDef.errorText != darkDef.errorText)
        #expect(lightDef.errorBackground != darkDef.errorBackground)
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

        let lightStandardErrorContrast = lightDef.errorText.contrastRatio(with: lightDef.background)
        let lightHCErrorContrast = lightHC.errorText.contrastRatio(with: lightHC.background)
        #expect(lightHCErrorContrast > lightStandardErrorContrast)

        let darkStandardErrorContrast = darkDef.errorText.contrastRatio(with: darkDef.background)
        let darkHCErrorContrast = darkHC.errorText.contrastRatio(with: darkHC.background)
        #expect(darkHCErrorContrast > darkStandardErrorContrast)
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

    @Test func highContrastTokensDifferFromStandard() {
        for preset in AppearancePreset.allCases {
            let standardDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: false
            )
            let highContrastDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: true
            )

            // 1. Token values must differ between standard and high contrast
            #expect(
                standardDefinition.secondaryText != highContrastDefinition.secondaryText,
                "secondaryText should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.codeKeyword != highContrastDefinition.codeKeyword,
                "codeKeyword should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.codeString != highContrastDefinition.codeString,
                "codeString should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.codeComment != highContrastDefinition.codeComment,
                "codeComment should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.codeNumber != highContrastDefinition.codeNumber,
                "codeNumber should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.errorText != highContrastDefinition.errorText,
                "errorText should differ in high contrast for \(preset)"
            )
            #expect(
                standardDefinition.errorBackground != highContrastDefinition.errorBackground,
                "errorBackground should differ in high contrast for \(preset)"
            )
        }
    }

    @Test func highContrastRatiosExceedStandard() {
        for preset in AppearancePreset.allCases {
            let standardDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: false
            )
            let highContrastDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: true
            )

            let standardSecContrast = standardDefinition.secondaryText.contrastRatio(
                with: standardDefinition.background
            )
            let highContrastSecContrast = highContrastDefinition.secondaryText.contrastRatio(
                with: highContrastDefinition.background
            )
            #expect(
                highContrastSecContrast > standardSecContrast,
                "High contrast secondaryText (\(highContrastSecContrast)) should exceed standard (\(standardSecContrast))"
            )

            let standardKeywordContrast = standardDefinition.codeKeyword.contrastRatio(
                with: standardDefinition.codeBackground
            )
            let highContrastKeywordContrast = highContrastDefinition.codeKeyword.contrastRatio(
                with: highContrastDefinition.codeBackground
            )
            #expect(
                highContrastKeywordContrast > standardKeywordContrast,
                "High contrast codeKeyword (\(highContrastKeywordContrast)) should exceed standard (\(standardKeywordContrast))"
            )

            let standardStringContrast = standardDefinition.codeString.contrastRatio(
                with: standardDefinition.codeBackground
            )
            let highContrastStringContrast = highContrastDefinition.codeString.contrastRatio(
                with: highContrastDefinition.codeBackground
            )
            #expect(
                highContrastStringContrast > standardStringContrast,
                "High contrast codeString (\(highContrastStringContrast)) should exceed standard (\(standardStringContrast))"
            )

            let standardCommentContrast = standardDefinition.codeComment.contrastRatio(
                with: standardDefinition.codeBackground
            )
            let highContrastCommentContrast = highContrastDefinition.codeComment.contrastRatio(
                with: highContrastDefinition.codeBackground
            )
            #expect(
                highContrastCommentContrast > standardCommentContrast,
                "High contrast codeComment (\(highContrastCommentContrast)) should exceed standard (\(standardCommentContrast))"
            )

            let standardNumberContrast = standardDefinition.codeNumber.contrastRatio(
                with: standardDefinition.codeBackground
            )
            let highContrastNumberContrast = highContrastDefinition.codeNumber.contrastRatio(
                with: highContrastDefinition.codeBackground
            )
            #expect(
                highContrastNumberContrast > standardNumberContrast,
                "High contrast codeNumber (\(highContrastNumberContrast)) should exceed standard (\(standardNumberContrast))"
            )

            let standardErrorContrast = standardDefinition.errorText.contrastRatio(
                with: standardDefinition.background
            )
            let highContrastErrorContrast = highContrastDefinition.errorText.contrastRatio(
                with: highContrastDefinition.background
            )
            #expect(
                highContrastErrorContrast > standardErrorContrast,
                "High contrast errorText (\(highContrastErrorContrast)) should exceed standard (\(standardErrorContrast))"
            )
        }
    }

    @Test func highContrastTokensMeetWCAGAA() {
        for preset in AppearancePreset.allCases {
            let standardDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: false
            )
            let highContrastDefinition = PresetPaletteDefinition.definition(
                for: preset,
                isDark: preset != .white,
                highContrast: true
            )

            let stdBg = standardDefinition.background
            let stdCodeBg = standardDefinition.codeBackground
            let hcBg = highContrastDefinition.background
            let hcCodeBg = highContrastDefinition.codeBackground

            #expect(standardDefinition.secondaryText.contrastRatio(with: stdBg) >= 4.5)
            #expect(highContrastDefinition.secondaryText.contrastRatio(with: hcBg) >= 4.5)
            #expect(standardDefinition.codeKeyword.contrastRatio(with: stdCodeBg) >= 4.5)
            #expect(highContrastDefinition.codeKeyword.contrastRatio(with: hcCodeBg) >= 4.5)
            #expect(standardDefinition.codeString.contrastRatio(with: stdCodeBg) >= 4.5)
            #expect(highContrastDefinition.codeString.contrastRatio(with: hcCodeBg) >= 4.5)
            #expect(standardDefinition.codeComment.contrastRatio(with: stdCodeBg) >= 4.5)
            #expect(highContrastDefinition.codeComment.contrastRatio(with: hcCodeBg) >= 4.5)
            #expect(standardDefinition.codeNumber.contrastRatio(with: stdCodeBg) >= 4.5)
            #expect(highContrastDefinition.codeNumber.contrastRatio(with: hcCodeBg) >= 4.5)
            #expect(standardDefinition.errorText.contrastRatio(with: stdBg) >= 4.5)
            #expect(highContrastDefinition.errorText.contrastRatio(with: hcBg) >= 4.5)
        }
    }
}
