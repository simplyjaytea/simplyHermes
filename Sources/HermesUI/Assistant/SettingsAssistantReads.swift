#if canImport(UIKit)
    import HermesKit

    /// The read-only answers of each assistant page (WP-53d). Each page loads its own list.
    enum SettingsAssistantReads {
        static let egressRead = SettingsAssistantRead(id: "egress", title: "Outbound connections") {
            try await $0.assistantEgressStatus()
        }

        static let sharedMetricsRead = SettingsAssistantRead(id: "sharedMetrics", title: "Shared metrics") {
            try await $0.assistantSharedMetricsConsent()
        }

        static let memoryRead = SettingsAssistantRead(id: "memory", title: "Memory") {
            try await $0.assistantMemory()
        }

        static let voiceConfigRead = SettingsAssistantRead(id: "voiceConfig", title: "Voice") {
            try await $0.assistantVoiceConfig()
        }

        static let voicesRead = SettingsAssistantRead(id: "voices", title: "ElevenLabs voices") {
            try await $0.assistantElevenLabsVoices()
        }

        static let curatorRead = SettingsAssistantRead(id: "curator", title: "Curator") {
            try await $0.assistantCurator()
        }

        static let workspacesRead = SettingsAssistantRead(id: "workspaces", title: "Workspaces") {
            try await $0.assistantWorkspaces()
        }

        static let themesRead = SettingsAssistantRead(
            id: "themes", title: "Themes",
            footer: "The server dashboard's look, for desktop parity. This page does not change the app's look."
        ) {
            try await $0.assistantDashboardThemes()
        }

        static let fontRead = SettingsAssistantRead(id: "font", title: "Font") {
            try await $0.assistantDashboardFont()
        }

        static let safetyReads = [egressRead, sharedMetricsRead]
        static let memoryReads = [memoryRead]
        static let voiceReads = [voiceConfigRead, voicesRead]
        static let workspaceReads = [workspacesRead]
        static let curatorReads = [curatorRead]
        static let appearanceReads = [themesRead, fontRead]
    }
#endif
