#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Assistant section of Settings: one row per assistant page (WP-53d). It sits between Server and Support.
    struct SettingsAssistantSection: View {
        let connections: ConnectionsModel

        var body: some View {
            Section("Assistant") {
                NavigationLink {
                    SettingsAssistantSafetyPage(model: model(SettingsAssistantReads.safetyReads))
                } label: {
                    Label("Safety", systemImage: "lock.shield")
                }
                .accessibilityIdentifier("settings.assistant.safety")
                NavigationLink {
                    SettingsAssistantMemoryPage(model: model(SettingsAssistantReads.memoryReads))
                } label: {
                    Label("Memory & context", systemImage: "brain")
                }
                .accessibilityIdentifier("settings.assistant.memory")
                NavigationLink {
                    SettingsAssistantVoicePage(model: model(SettingsAssistantReads.voiceReads))
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                .accessibilityIdentifier("settings.assistant.voice")
                NavigationLink {
                    SettingsAssistantWorkspacePage(model: model(SettingsAssistantReads.workspaceReads))
                } label: {
                    Label("Workspace", systemImage: "folder")
                }
                .accessibilityIdentifier("settings.assistant.workspace")
                NavigationLink {
                    SettingsAssistantCuratorPage(model: model(SettingsAssistantReads.curatorReads))
                } label: {
                    Label("Curator", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.assistant.curator")
                NavigationLink {
                    SettingsAssistantAppearancePage(model: model(SettingsAssistantReads.appearanceReads))
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .accessibilityIdentifier("settings.assistant.appearance")
            }
        }

        private func model(_ reads: [SettingsAssistantRead]) -> SettingsAssistantModel {
            SettingsAssistantModel(connections: connections, reads: reads)
        }
    }
#endif
