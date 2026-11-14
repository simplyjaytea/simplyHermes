#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Appearance: lists labeled choices with selected markers, a local sample conversation
    /// preview, and reset-to-System (plan WP-20 / design direction v2).
    ///
    /// The preference updates immediately across the app and is stored on this device only.
    public struct AppearanceSettingsScreen: View {
        @AppStorage(AppearanceSettings.key) private var storedPresetRaw: String = AppearancePreset.system.rawValue
        @Environment(\.hermesPalette) private var palette

        public init() {}

        private var activePreset: AppearancePreset {
            AppearancePreset.fallback(for: storedPresetRaw)
        }

        public var body: some View {
            List {
                Section {
                    ForEach(AppearancePreset.allCases, id: \.self) { preset in
                        presetRow(preset)
                    }
                } header: {
                    Text("Themes")
                } footer: {
                    Text("Appearance presets are saved on this device and apply across simplyHermes.")
                        .font(HermesFont.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .listRowBackground(palette.card)

                Section("Preview") {
                    VStack(alignment: .leading, spacing: HermesMetrics.bubbleSpacing) {
                        Text("Example conversation")
                            .font(HermesFont.caption.weight(.medium))
                            .foregroundStyle(palette.secondaryText)
                            .padding(.horizontal, 4)

                        MessageBubble(
                            role: .user,
                            text: "How do the color tokens look in this theme?"
                        )

                        MessageBubble(
                            role: .assistant,
                            text: "Here is a preview of assistant text, tool output, and an approval prompt."
                        )

                        ToolOutputBubble(
                            command: "swift --version",
                            output: "Swift version 6.1.2 (example output)",
                            duration: "0.1s"
                        )

                        ApprovalBubble(
                            command: "echo 'Reviewing appearance preview'",
                            isEnabled: false,
                            allowsFeedback: false,
                            onDeny: {},
                            onApprove: {}
                        )

                        sampleComposer
                    }
                    .padding(.vertical, 8)
                    // The live preview renders with the active palette
                    .hermesAppearance(activePreset)
                    .background(HermesPalette.palette(for: activePreset).background)
                    .clipShape(RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous)
                            .strokeBorder(HermesPalette.palette(for: activePreset).separator, lineWidth: 1)
                    )
                }
                .listRowBackground(palette.card)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                Section {
                    Button(role: .destructive) {
                        selectPreset(.system)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset to System")
                                .font(HermesFont.body.weight(.medium))
                            Spacer()
                        }
                        .frame(minHeight: HermesMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("appearance.reset")
                    .accessibilityLabel("Reset appearance to System")
                }
                .listRowBackground(palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .toolbarBackground(palette.groupedBackground, for: .navigationBar)
            .navigationTitle("Appearance")
        }

        private func presetRow(_ preset: AppearancePreset) -> some View {
            let isSelected = activePreset == preset
            return Button {
                selectPreset(preset)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.displayName)
                            .font(HermesFont.body.weight(.medium))
                            .foregroundStyle(palette.primaryText)

                        Text(preset.subtitle)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(HermesFont.body.weight(.bold))
                            .foregroundStyle(HermesPalette.palette(for: activePreset).accent)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: HermesMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("appearance.preset.\(preset.rawValue)")
            .accessibilityLabel(preset.displayName)
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityHint(preset.subtitle)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        }

        private func selectPreset(_ preset: AppearancePreset) {
            // Instant app-wide update with no transition animation required
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                storedPresetRaw = preset.rawValue
            }
        }

        private var sampleComposer: some View {
            let palette = HermesPalette.palette(for: activePreset)
            return HStack(spacing: 8) {
                Text("Message Hermes…")
                    .font(HermesFont.body)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.fill, in: Capsule())

                Image(systemName: "arrow.up")
                    .font(HermesFont.body.weight(.bold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: 32, height: 32)
                    .background(palette.accent, in: Circle())
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)
        }
    }

    #Preview("System", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.system)
    }

    #Preview("Dark", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.dark)
    }

    #Preview("Blue", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.blue)
    }

    #Preview("White", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.white)
    }

    #Preview("Inner portrait, Blue", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.blue)
    }

    #Preview("Inner landscape, Blue", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.blue)
    }

    #Preview("Half-fold, Dark", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            AppearanceSettingsScreen()
        }
        .hermesAppearance(.dark)
    }
#endif
