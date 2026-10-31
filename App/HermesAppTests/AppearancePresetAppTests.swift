import HermesKit
import HermesUI
import SwiftUI
import Testing

@MainActor
struct AppearancePresetAppTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suite = "test.appearance.app.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    @Test func systemPaletteRetainsNativeLook() {
        let palette = HermesPalette.palette(for: .system)
        #expect(palette.preset == .system)
        #expect(palette.colorScheme == nil)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == HermesColor.onAccent)
        #expect(palette.outgoingBubble == HermesColor.outgoingBubble)
        #expect(palette.destructive == Color(red: 220 / 255.0, green: 38 / 255.0, blue: 38 / 255.0))
        #expect(palette.onDestructive == Color.white)
    }

    @Test func darkPaletteEnforcesDarkSchemeAndDistinctSurfaces() {
        let palette = HermesPalette.palette(for: .dark)
        #expect(palette.preset == .dark)
        #expect(palette.colorScheme == .dark)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == Color.white)
        #expect(palette.onDestructive == Color.white)
        #expect(palette != HermesPalette.palette(for: .white))
        #expect(palette != HermesPalette.palette(for: .blue))
    }

    @Test func bluePaletteProvidesNavySurfacesWithDarkScheme() {
        let palette = HermesPalette.palette(for: .blue)
        #expect(palette.preset == .blue)
        #expect(palette.colorScheme == .dark)
        #expect(palette.onAccent == Color.white)
        #expect(palette.onDestructive == Color.white)
        #expect(palette != HermesPalette.palette(for: .dark))
    }

    @Test func whitePaletteEnforcesLightSchemeAndReadableText() {
        let palette = HermesPalette.palette(for: .white)
        #expect(palette.preset == .white)
        #expect(palette.colorScheme == .light)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == Color.white)
        #expect(palette.onDestructive == Color.white)
        #expect(palette != HermesPalette.palette(for: .system))
    }

    @Test func allPresetsProduceValidUniquePalettes() {
        var presets: [AppearancePreset: HermesPalette] = [:]
        for preset in AppearancePreset.allCases {
            let palette = HermesPalette.palette(for: preset)
            #expect(palette.preset == preset)
            presets[preset] = palette
        }
        #expect(presets.count == 4)
    }

    @Test func environmentDefaultsMatchSystemPalette() {
        let defaultPalette = HermesPalette.system
        #expect(defaultPalette.preset == .system)
        #expect(defaultPalette.colorScheme == nil)
    }

    @Test func persistenceAcrossSimulatedRelaunchWithIsolatedDefaults() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Initial launch: defaults to System
        let launch1Settings = AppearanceSettings(defaults: defaults)
        #expect(launch1Settings.preset == .system)

        // Select Blue preset
        launch1Settings.preset = .blue
        #expect(defaults.string(forKey: AppearanceSettings.key) == "blue")

        // Simulated Relaunch 1: Fresh settings instance reading from disk
        let launch2Settings = AppearanceSettings(defaults: defaults)
        #expect(launch2Settings.preset == .blue)
        let bluePalette = HermesPalette.palette(for: launch2Settings.preset)
        #expect(bluePalette.preset == .blue)
        #expect(bluePalette.colorScheme == .dark)

        // Change to Dark preset
        launch2Settings.preset = .dark
        #expect(defaults.string(forKey: AppearanceSettings.key) == "dark")

        // Simulated Relaunch 2
        let launch3Settings = AppearanceSettings(defaults: defaults)
        #expect(launch3Settings.preset == .dark)
        let darkPalette = HermesPalette.palette(for: launch3Settings.preset)
        #expect(darkPalette.preset == .dark)
        #expect(darkPalette.colorScheme == .dark)

        // Change to White preset
        launch3Settings.preset = .white
        #expect(defaults.string(forKey: AppearanceSettings.key) == "white")

        // Simulated Relaunch 3
        let launch4Settings = AppearanceSettings(defaults: defaults)
        #expect(launch4Settings.preset == .white)
        let whitePalette = HermesPalette.palette(for: launch4Settings.preset)
        #expect(whitePalette.preset == .white)
        #expect(whitePalette.colorScheme == .light)

        // Reset restores System
        launch4Settings.reset()
        #expect(defaults.object(forKey: AppearanceSettings.key) == nil)

        // Simulated Relaunch 4
        let launch5Settings = AppearanceSettings(defaults: defaults)
        #expect(launch5Settings.preset == .system)
    }

    @Test func viewModifierAppliesPaletteAndScheme() {
        for preset in AppearancePreset.allCases {
            let palette = HermesPalette.palette(for: preset)
            #expect(palette.preset == preset)

            let expectedScheme: ColorScheme? = {
                switch preset {
                case .system: nil
                case .dark, .blue: .dark
                case .white: .light
                }
            }()
            #expect(palette.colorScheme == expectedScheme)

            // Verify destructive and onDestructive tokens exist and are accessible
            let def = PresetPaletteDefinition.definition(for: preset)
            let buttonContrast = def.onDestructive.contrastRatio(with: def.destructive)
            #expect(buttonContrast >= 4.5, "Button contrast below 4.5:1 for \(preset): \(buttonContrast)")
        }
    }
}
