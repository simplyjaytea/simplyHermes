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
            let def = PresetPaletteDefinition.definition(for: preset)
            let checks = def.contrastChecks

            // Normal text on background must meet WCAG AA (>= 4.5:1)
            let primaryOnBg = try! #require(checks["primaryOnBackground"])
            #expect(primaryOnBg >= 4.5, "Failed primaryOnBg for \(preset): \(primaryOnBg)")

            // Normal text on incoming bubble must meet WCAG AA (>= 4.5:1)
            let primaryOnBubble = try! #require(checks["primaryOnIncomingBubble"])
            #expect(primaryOnBubble >= 4.5, "Failed primaryOnBubble for \(preset): \(primaryOnBubble)")

            // Secondary text on background must meet at least large text/UI requirement (>= 3.0:1)
            let secOnBg = try! #require(checks["secondaryOnBackground"])
            #expect(secOnBg >= 3.0, "Failed secOnBg for \(preset): \(secOnBg)")

            // Secondary text on bubble must meet at least large text/UI requirement (>= 3.0:1)
            let secOnBubble = try! #require(checks["secondaryOnIncomingBubble"])
            #expect(secOnBubble >= 3.0, "Failed secOnBubble for \(preset): \(secOnBubble)")

            // Button text (onAccent) on accent fill must meet WCAG AA (>= 4.5:1)
            let onAccent = try! #require(checks["onAccentOnAccent"])
            #expect(onAccent >= 4.5, "Failed onAccent for \(preset): \(onAccent)")

            // Outgoing bubble text (onAccent) on bubble fill must meet WCAG AA (>= 4.5:1)
            let onOutgoing = try! #require(checks["onAccentOnOutgoingBubble"])
            #expect(onOutgoing >= 4.5, "Failed onOutgoing for \(preset): \(onOutgoing)")

            // Code text on code background must meet WCAG AA (>= 4.5:1)
            let codeContrast = try! #require(checks["codeTextOnCodeBackground"])
            #expect(codeContrast >= 4.5, "Failed codeContrast for \(preset): \(codeContrast)")
        }
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
