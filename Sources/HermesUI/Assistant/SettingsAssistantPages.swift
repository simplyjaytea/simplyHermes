#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Assistant > Voice: the server's voice configuration and its ElevenLabs voices, as read (WP-53d).
    struct SettingsAssistantVoicePage: View {
        @State private var model: SettingsAssistantModel

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let config = model.panel("voiceConfig") {
                    SettingsAssistantPanelSection(panel: config)
                }
                if let voices = model.panel("voices") {
                    SettingsAssistantPanelSection(panel: voices)
                }
            }
            .navigationTitle("Voice")
            .settingsAssistantLoads(model)
        }
    }

    /// Settings > Assistant > Workspace: the chat workspaces, with a scan to look again (WP-53d).
    struct SettingsAssistantWorkspacePage: View {
        @State private var model: SettingsAssistantModel

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let workspaces = model.panel("workspaces") {
                    SettingsAssistantPanelSection(panel: workspaces)
                }
                Section {
                    Button("Scan for workspaces") { scan() }
                        .accessibilityIdentifier("assistant.workspace.scan")
                } footer: {
                    Text("Asks the server to look for workspaces again.")
                }
            }
            .navigationTitle("Workspace")
            .settingsAssistantLoads(model)
        }

        private func scan() {
            Task {
                await model.change("Scan requested.") {
                    try await $0.scanAssistantWorkspaces()
                }
            }
        }
    }

    /// Settings > Assistant > Appearance: the server dashboard's theme and font, as read. The app's own look is not
    /// changed here (WP-53d). Pickers are not built: their writes are status only and not verified [JT].
    struct SettingsAssistantAppearancePage: View {
        @State private var model: SettingsAssistantModel

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let themes = model.panel("themes") {
                    SettingsAssistantPanelSection(panel: themes)
                }
                if let font = model.panel("font") {
                    SettingsAssistantPanelSection(panel: font)
                }
            }
            .navigationTitle("Appearance")
            .settingsAssistantLoads(model)
        }
    }

    @MainActor
    private func voicePreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.voiceReads,
            answers: [
                "voiceConfig": SettingsAssistantSamples.voiceConfig,
                "voices": SettingsAssistantSamples.voices,
            ])
    }

    @MainActor
    private func workspacePreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.workspaceReads,
            answers: ["workspaces": SettingsAssistantSamples.workspaces])
    }

    @MainActor
    private func appearancePreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.appearanceReads,
            answers: [
                "themes": SettingsAssistantSamples.themes,
                "font": SettingsAssistantSamples.font,
            ])
    }

    #Preview("Voice, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantVoicePage(model: voicePreview()) }
    }

    #Preview("Voice, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantVoicePage(model: voicePreview()) }
    }

    #Preview("Voice, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantVoicePage(model: voicePreview()) }
    }

    #Preview("Voice, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantVoicePage(model: voicePreview()) }
    }

    #Preview("Workspace, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantWorkspacePage(model: workspacePreview()) }
    }

    #Preview("Workspace, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantWorkspacePage(model: workspacePreview()) }
    }

    #Preview("Workspace, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantWorkspacePage(model: workspacePreview()) }
    }

    #Preview("Workspace, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantWorkspacePage(model: workspacePreview()) }
    }

    #Preview("Appearance, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantAppearancePage(model: appearancePreview()) }
    }

    #Preview("Appearance, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantAppearancePage(model: appearancePreview()) }
    }

    #Preview("Appearance, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantAppearancePage(model: appearancePreview()) }
    }

    #Preview("Appearance, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantAppearancePage(model: appearancePreview()) }
    }
#endif
