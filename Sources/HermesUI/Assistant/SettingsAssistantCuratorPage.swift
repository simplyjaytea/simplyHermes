#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Assistant > Curator: the curator's status, pause and resume, and a run now (WP-53d).
    struct SettingsAssistantCuratorPage: View {
        @State private var model: SettingsAssistantModel
        @State private var confirmsRun = false

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let curator = model.panel("curator") {
                    SettingsAssistantPanelSection(panel: curator)
                }
                Section {
                    Button("Pause") { setPaused(true) }
                        .accessibilityIdentifier("assistant.curator.pause")
                    Button("Resume") { setPaused(false) }
                        .accessibilityIdentifier("assistant.curator.resume")
                    Button("Run now") { confirmsRun = true }
                        .accessibilityIdentifier("assistant.curator.run")
                } footer: {
                    Text("Run now starts one run of the curator on the server.")
                }
            }
            .navigationTitle("Curator")
            .settingsAssistantLoads(model)
            .confirmationDialog(
                "Run the curator now?", isPresented: $confirmsRun, titleVisibility: .visible
            ) {
                Button("Run now") { run() }
            } message: {
                Text("The curator runs once, now.")
            }
        }

        private func setPaused(_ paused: Bool) {
            Task {
                await model.change(paused ? "Curator is paused." : "Curator is resumed.") {
                    try await $0.setAssistantCuratorPaused(paused)
                }
            }
        }

        private func run() {
            Task {
                await model.change("Curator run started.") {
                    try await $0.runAssistantCurator()
                }
            }
        }
    }

    @MainActor
    private func curatorPreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.curatorReads,
            answers: ["curator": ["paused": false]])
    }

    #Preview("Curator, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantCuratorPage(model: curatorPreview()) }
    }

    #Preview("Curator, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantCuratorPage(model: curatorPreview()) }
    }

    #Preview("Curator, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantCuratorPage(model: curatorPreview()) }
    }

    #Preview("Curator, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantCuratorPage(model: curatorPreview()) }
    }
#endif
