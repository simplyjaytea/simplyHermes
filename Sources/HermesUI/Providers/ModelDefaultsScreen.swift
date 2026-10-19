#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Model defaults: the main model, its provider and reasoning effort (WP-53a).
    struct ModelDefaultsScreen: View {
        @State private var model: ModelDefaultsModel

        init(connections: ConnectionsModel) {
            _model = State(initialValue: ModelDefaultsModel(connections: connections))
        }

        init(model: ModelDefaultsModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            Form {
                Section {
                    LabeledContent("Model") {
                        Text(model.current?.model ?? "Not set")
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    LabeledContent("Provider") {
                        Text(model.current?.provider ?? "Not set")
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                    if let context = model.current?.effectiveContextLength {
                        LabeledContent("Context") {
                            Text("\(context) tokens")
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                } header: {
                    Text("Now")
                }
                Section {
                    Picker("Provider", selection: $model.providerSlug) {
                        ForEach(model.providers) { provider in
                            Text(provider.name).tag(provider.slug)
                        }
                    }
                    .accessibilityIdentifier("models.provider")
                    TextField("Model id", text: $model.modelId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("models.model")
                    if !model.suggestedModels.isEmpty {
                        Menu("Suggested models") {
                            ForEach(model.suggestedModels, id: \.self) { id in
                                Button(id) { model.modelId = id }
                            }
                        }
                    }
                    Button("Use the recommended model") {
                        Task { await model.useRecommended() }
                    }
                    .disabled(model.providerSlug.isEmpty || model.isWorking)
                    Picker("Reasoning effort", selection: $model.effort) {
                        Text("Keep current").tag("")
                        ForEach(ModelDefaultsEffort.options, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                } header: {
                    Text("Change")
                } footer: {
                    Text("Running chats keep their model. New chats use the new one.")
                }
                Section {
                    Button("Save") {
                        Task { await model.save() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("models.save")
                    if let savedText = model.savedText {
                        Text(savedText).foregroundStyle(HermesColor.secondaryText)
                    }
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Model defaults")
            .task { await model.load() }
        }
    }

    #Preview("Model defaults, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ModelDefaultsScreen(model: sampleModel()) }
    }

    #Preview("Model defaults, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ModelDefaultsScreen(model: sampleModel()) }
    }

    #Preview("Model defaults, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ModelDefaultsScreen(model: sampleModel()) }
    }

    #Preview("Model defaults, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ModelDefaultsScreen(model: sampleModel()) }
    }

    /// A model with sample answers and no connection, for previews.
    @MainActor
    private func sampleModel() -> ModelDefaultsModel {
        ModelDefaultsModel(
            connections: .preview(), current: ProviderSamples.modelInfo, providers: ProviderSamples.providers)
    }
#endif
