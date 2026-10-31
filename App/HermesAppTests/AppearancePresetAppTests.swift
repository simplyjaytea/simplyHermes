import HermesKit
import HermesUI
import SwiftUI
import Testing

@MainActor
struct AppearancePresetAppTests {
    @Test func systemPaletteRetainsNativeLook() {
        let palette = HermesPalette.palette(for: .system)
        #expect(palette.preset == .system)
        #expect(palette.colorScheme == nil)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == HermesColor.onAccent)
        #expect(palette.outgoingBubble == HermesColor.outgoingBubble)
    }

    @Test func darkPaletteEnforcesDarkSchemeAndDistinctSurfaces() {
        let palette = HermesPalette.palette(for: .dark)
        #expect(palette.preset == .dark)
        #expect(palette.colorScheme == .dark)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == Color.white)
        #expect(palette != HermesPalette.palette(for: .white))
        #expect(palette != HermesPalette.palette(for: .blue))
    }

    @Test func bluePaletteProvidesNavySurfacesWithDarkScheme() {
        let palette = HermesPalette.palette(for: .blue)
        #expect(palette.preset == .blue)
        #expect(palette.colorScheme == .dark)
        #expect(palette.onAccent == Color.white)
        #expect(palette != HermesPalette.palette(for: .dark))
    }

    @Test func whitePaletteEnforcesLightSchemeAndReadableText() {
        let palette = HermesPalette.palette(for: .white)
        #expect(palette.preset == .white)
        #expect(palette.colorScheme == .light)
        #expect(palette.accent == HermesColor.accent)
        #expect(palette.onAccent == Color.white)
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
}
