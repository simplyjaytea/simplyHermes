#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Assistant > Safety: outbound access, shared metrics and the security audit (WP-53d).
    struct SettingsAssistantSafetyPage: View {
        @State private var model: SettingsAssistantModel

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let egress = model.panel("egress") {
                    SettingsAssistantPanelSection(panel: egress)
                }
                if let metrics = model.panel("sharedMetrics") {
                    SettingsAssistantPanelSection(panel: metrics)
                }
                Section {
                    Button("Allow sharing") { setSharing(true) }
                        .accessibilityIdentifier("assistant.safety.allowSharing")
                    Button("Stop sharing") { setSharing(false) }
                        .accessibilityIdentifier("assistant.safety.stopSharing")
                }
                Section {
                    Button("Run security audit") { runAudit() }
                        .accessibilityIdentifier("assistant.safety.audit")
                } footer: {
                    Text("Runs the audit on the server. Its answer appears below.")
                }
                if let audit = model.panel("audit") {
                    SettingsAssistantPanelSection(panel: audit)
                }
            }
            .navigationTitle("Safety")
            .settingsAssistantLoads(model)
        }

        private func setSharing(_ enabled: Bool) {
            Task {
                await model.change(enabled ? "Shared metrics are on." : "Shared metrics are off.") {
                    try await $0.setAssistantSharedMetricsConsent(enabled: enabled)
                }
            }
        }

        private func runAudit() {
            Task {
                await model.showAnswer(panel: "audit", title: "Security audit") {
                    try await $0.runAssistantSecurityAudit()
                }
            }
        }
    }

    @MainActor
    private func safetyPreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.safetyReads,
            answers: [
                "egress": ["status": "ok"],
                "sharedMetrics": ["enabled": false],
            ])
    }

    #Preview("Safety, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantSafetyPage(model: safetyPreview()) }
    }

    #Preview("Safety, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantSafetyPage(model: safetyPreview()) }
    }

    #Preview("Safety, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantSafetyPage(model: safetyPreview()) }
    }

    #Preview("Safety, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantSafetyPage(model: safetyPreview()) }
    }
#endif
