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

    @Test func launchResetIsolatesDirtyPresetOnLaunch() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Simulate dirty state from prior session
        let dirtySettings = AppearanceSettings(defaults: defaults)
        dirtySettings.preset = .blue
        #expect(defaults.string(forKey: AppearanceSettings.key) == "blue")
        #expect(dirtySettings.preset == .blue)

        // 2. Normal launch without reset argument preserves dirty state
        #expect(defaults.bool(forKey: "HermesResetAppearance") == false)
        let normalLaunch = LaunchOptions(defaults: defaults)
        HermesApp.applyLaunchReset(normalLaunch, defaults: defaults)
        let unresetSettings = AppearanceSettings(defaults: defaults)
        #expect(unresetSettings.preset == .blue)

        // 3. Launch with -HermesResetAppearance YES (as evaluated by LaunchOptions and HermesApp.applyLaunchReset)
        defaults.set(true, forKey: "HermesResetAppearance")
        let resetLaunch = LaunchOptions(defaults: defaults)
        #expect(resetLaunch.resetAppearance)
        HermesApp.applyLaunchReset(resetLaunch, defaults: defaults)

        // 4. Executable proof of isolation: preset is cleanly restored to system and key is removed
        let cleanSettings = AppearanceSettings(defaults: defaults)
        #expect(cleanSettings.preset == .system)
        #expect(defaults.object(forKey: AppearanceSettings.key) == nil)
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

            // Verify errorText and errorBackground tokens exist and are accessible
            let errorTextContrast = def.errorText.contrastRatio(with: def.background)
            #expect(errorTextContrast >= 4.5, "errorText contrast below 4.5:1 for \(preset): \(errorTextContrast)")
            let errorCardContrast = def.errorText.contrastRatio(with: def.errorBackground)
            #expect(
                errorCardContrast >= 4.5, "errorText on errorBackground below 4.5:1 for \(preset): \(errorCardContrast)"
            )
        }
    }

    #if canImport(UIKit)
        private struct EnvironmentProbe: View {
            @Environment(\.hermesPalette) var palette
            @Environment(\.hermesAppearancePreset) var preset
            let onRead: (AppearancePreset, HermesPalette) -> Void

            var body: some View {
                Text("probe")
                    .onAppear {
                        onRead(preset, palette)
                    }
            }
        }

        @Test func viewModifierActivelyPropagatesEnvironmentPalette() {
            for preset in AppearancePreset.allCases {
                var capturedPreset: AppearancePreset?
                var capturedPalette: HermesPalette?

                let probe = EnvironmentProbe { currentPreset, currentPalette in
                    capturedPreset = currentPreset
                    capturedPalette = currentPalette
                }
                .hermesAppearance(preset)

                let host = UIHostingController(rootView: probe)
                _ = host.view
                host.view.layoutIfNeeded()

                #expect(capturedPreset == preset)
                #expect(capturedPalette?.preset == preset)
            }
        }

        @Test func dynamicSystemUIColorAdaptsToTraits() {
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            let highContrastLightTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: .high),
            ])
            let highContrastDarkTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(accessibilityContrast: .high),
            ])

            let keywordColor = HermesPalette.dynamicSystemUIColor(\.codeKeyword)
            let lightKeyword = keywordColor.resolvedColor(with: lightTraits)
            let darkKeyword = keywordColor.resolvedColor(with: darkTraits)
            let hcLightKeyword = keywordColor.resolvedColor(with: highContrastLightTraits)
            let hcDarkKeyword = keywordColor.resolvedColor(with: highContrastDarkTraits)

            #expect(lightKeyword != darkKeyword)
            #expect(hcLightKeyword != lightKeyword)
            #expect(hcDarkKeyword != darkKeyword)

            let secColor = HermesPalette.dynamicSystemUIColor(\.secondaryText)
            let lightSec = secColor.resolvedColor(with: lightTraits)
            let darkSec = secColor.resolvedColor(with: darkTraits)
            #expect(lightSec != darkSec)

            let errorTextColor = HermesPalette.dynamicSystemUIColor(\.errorText)
            let lightErrorText = errorTextColor.resolvedColor(with: lightTraits)
            let darkErrorText = errorTextColor.resolvedColor(with: darkTraits)
            #expect(lightErrorText != darkErrorText)

            let errorBgColor = HermesPalette.dynamicSystemUIColor(\.errorBackground)
            let lightErrorBg = errorBgColor.resolvedColor(with: lightTraits)
            let darkErrorBg = errorBgColor.resolvedColor(with: darkTraits)
            #expect(lightErrorBg != darkErrorBg)

            // Trait-resolved palette helper checks
            let resolvedDark = HermesPalette.palette(for: .system, traits: darkTraits)
            #expect(resolvedDark.preset == .system)
            #expect(resolvedDark.colorScheme == .dark)

            let resolvedLight = HermesPalette.palette(for: .system, traits: lightTraits)
            #expect(resolvedLight.preset == .system)
            #expect(resolvedLight.colorScheme == .light)
        }

        @Test func dynamicUIColorAdaptsToTraitsForAllPresets() {
            let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
            let highContrastDarkTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(accessibilityContrast: .high),
            ])
            let lightTraits = UITraitCollection(userInterfaceStyle: .light)
            let highContrastLightTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(accessibilityContrast: .high),
            ])

            for preset in AppearancePreset.allCases {
                let standardTraits = (preset == .white) ? lightTraits : darkTraits
                let highContrastTraits = (preset == .white) ? highContrastLightTraits : highContrastDarkTraits

                let keywordColor = HermesPalette.dynamicUIColor(for: preset, \.codeKeyword)
                let standardKeyword = keywordColor.resolvedColor(with: standardTraits)
                let highContrastKeyword = keywordColor.resolvedColor(with: highContrastTraits)
                #expect(
                    standardKeyword != highContrastKeyword,
                    "codeKeyword should adapt to high contrast for \(preset)"
                )

                let secondaryTextColor = HermesPalette.dynamicUIColor(for: preset, \.secondaryText)
                let standardSec = secondaryTextColor.resolvedColor(with: standardTraits)
                let highContrastSec = secondaryTextColor.resolvedColor(with: highContrastTraits)
                #expect(
                    standardSec != highContrastSec,
                    "secondaryText should adapt to high contrast for \(preset)"
                )

                let errorTextColor = HermesPalette.dynamicUIColor(for: preset, \.errorText)
                let standardErrorText = errorTextColor.resolvedColor(with: standardTraits)
                let highContrastErrorText = errorTextColor.resolvedColor(with: highContrastTraits)
                #expect(
                    standardErrorText != highContrastErrorText,
                    "errorText should adapt to high contrast for \(preset)"
                )

                let errorBgColor = HermesPalette.dynamicUIColor(for: preset, \.errorBackground)
                let standardErrorBg = errorBgColor.resolvedColor(with: standardTraits)
                let highContrastErrorBg = errorBgColor.resolvedColor(with: highContrastTraits)
                #expect(
                    standardErrorBg != highContrastErrorBg,
                    "errorBackground should adapt to high contrast for \(preset)"
                )
            }
        }

        @Test func uiHostingControllerRenderedHarness() {
            // Render screen and sample chat bubbles inside UIHostingController
            for preset in AppearancePreset.allCases {
                let screenView = AppearanceSettingsScreen().hermesAppearance(preset)
                let host = UIHostingController(rootView: screenView)
                _ = host.view
                host.view.bounds = CGRect(x: 0, y: 0, width: 393, height: 852)
                host.view.layoutIfNeeded()
                #expect(!host.view.subviews.isEmpty)

                // Render sample bubbles wrapped in palette
                let bubbleView = VStack {
                    MessageBubble(role: .user, text: "Rendered test user message")
                    MessageBubble(role: .assistant, text: "Rendered test assistant message")
                    ToolOutputBubble(command: "ls -la", output: "total 0", duration: "0.01s")
                    ApprovalBubble(
                        command: "reboot",
                        isEnabled: false,
                        allowsFeedback: false,
                        onDeny: {},
                        onApprove: {}
                    )
                }
                .hermesAppearance(preset)

                let bubbleHost = UIHostingController(rootView: bubbleView)
                _ = bubbleHost.view
                bubbleHost.view.bounds = CGRect(x: 0, y: 0, width: 393, height: 400)
                bubbleHost.view.layoutIfNeeded()
                #expect(!bubbleHost.view.subviews.isEmpty)
            }
        }
    #endif
}
