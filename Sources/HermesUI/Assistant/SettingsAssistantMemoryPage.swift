#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Assistant > Memory & context: the memory status and the reset (WP-53d). The provider picker and the
    /// provider settings are not here yet: their writes are status only and not verified against a server [JT].
    struct SettingsAssistantMemoryPage: View {
        @State private var model: SettingsAssistantModel
        @State private var confirmsReset = false

        init(model: SettingsAssistantModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                SettingsAssistantStatus(model: model)
                if let memory = model.panel("memory") {
                    SettingsAssistantPanelSection(panel: memory)
                }
                Section {
                    Button("Reset memory", role: .destructive) {
                        confirmsReset = true
                    }
                    .accessibilityIdentifier("assistant.memory.reset")
                } footer: {
                    Text("Resets all memory on the server.")
                }
            }
            .navigationTitle("Memory & context")
            .settingsAssistantLoads(model)
            .confirmationDialog(
                "Reset all memory?", isPresented: $confirmsReset, titleVisibility: .visible
            ) {
                Button("Reset memory", role: .destructive) { reset() }
            } message: {
                Text("This can't be undone.")
            }
        }

        private func reset() {
            Task {
                await model.change("Memory reset requested.") {
                    try await $0.resetAssistantMemory()
                }
            }
        }
    }

    @MainActor
    private func memoryPreview() -> SettingsAssistantModel {
        .preview(
            reads: SettingsAssistantReads.memoryReads,
            answers: ["memory": SettingsAssistantSamples.memory])
    }

    #Preview("Memory, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SettingsAssistantMemoryPage(model: memoryPreview()) }
    }

    #Preview("Memory, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SettingsAssistantMemoryPage(model: memoryPreview()) }
    }

    #Preview("Memory, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SettingsAssistantMemoryPage(model: memoryPreview()) }
    }

    #Preview("Memory, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SettingsAssistantMemoryPage(model: memoryPreview()) }
    }
#endif
