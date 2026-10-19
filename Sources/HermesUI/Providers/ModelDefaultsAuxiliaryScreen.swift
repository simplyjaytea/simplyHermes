#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Auxiliary models: one row per task, each with its own reasoning effort (WP-53a).
    struct ModelDefaultsAuxiliaryScreen: View {
        @State private var model: ModelDefaultsAuxiliaryModel

        init(connections: ConnectionsModel) {
            _model = State(initialValue: ModelDefaultsAuxiliaryModel(connections: connections))
        }

        init(model: ModelDefaultsAuxiliaryModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                if let main = model.main {
                    Section {
                        LabeledContent("Model") {
                            Text(main.model ?? "Not set")
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                        LabeledContent("Provider") {
                            Text(main.provider ?? "Not set")
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    } header: {
                        Text("Main model")
                    }
                }
                Section {
                    ForEach(model.tasks) { task in
                        ModelDefaultsAuxiliaryRow(task: task) { effort in
                            Task { await model.setEffort(effort, for: task) }
                        }
                    }
                } header: {
                    Text("Tasks")
                } footer: {
                    Text("A picked effort is sent at once. The list is read again after each change.")
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Auxiliary models")
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }

    /// One auxiliary task: its name, the model it runs, the effort the server stores, and a menu to set the effort.
    struct ModelDefaultsAuxiliaryRow: View {
        let task: ModelDefaultsAuxiliaryTask
        let onPick: (String) -> Void

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.task)
                        .font(HermesFont.body.weight(.semibold))
                    Text(routeText)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                    Text(effortText)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Spacer(minLength: 8)
                Menu {
                    ForEach(ModelDefaultsEffort.options, id: \.self) { value in
                        Button(value) { onPick(value) }
                    }
                } label: {
                    Label("Effort", systemImage: "gauge")
                }
                .accessibilityIdentifier("auxiliary.effort.\(task.task)")
            }
        }

        private var routeText: String {
            let provider = task.provider?.providerNonEmpty ?? "auto"
            guard let model = task.model?.providerNonEmpty else { return provider }
            return provider + " · " + model
        }

        private var effortText: String {
            guard let effort = task.reasoningEffort?.providerNonEmpty else { return "Effort: default" }
            return "Effort: " + effort
        }
    }

    #Preview("Auxiliary models, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ModelDefaultsAuxiliaryScreen(model: sampleModel()) }
    }

    #Preview("Auxiliary models, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ModelDefaultsAuxiliaryScreen(model: sampleModel()) }
    }

    #Preview("Auxiliary models, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ModelDefaultsAuxiliaryScreen(model: sampleModel()) }
    }

    #Preview("Auxiliary models, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ModelDefaultsAuxiliaryScreen(model: sampleModel()) }
    }

    /// A model with sample answers and no connection, for previews.
    @MainActor
    private func sampleModel() -> ModelDefaultsAuxiliaryModel {
        ModelDefaultsAuxiliaryModel(
            connections: .preview(), tasks: ProviderSamples.auxiliary?.tasks ?? [],
            main: ProviderSamples.auxiliary?.main)
    }
#endif
