#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The main model: what it is now, and the provider, model and effort to switch to (WP-53a).
    @MainActor
    @Observable
    final class ModelDefaultsModel {
        private(set) var current: ModelInfo?
        /// Providers with credentials on this server. A provider that is not set up cannot be the main one.
        private(set) var providers: [ModelProviderOptions] = []
        var providerSlug = ""
        var modelId = ""
        /// Empty keeps the stored effort, so nothing is sent for it.
        var effort = ""
        private(set) var isWorking = false
        private(set) var errorText: String?
        private(set) var savedText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel, current: ModelInfo? = nil, providers: [ModelProviderOptions] = []) {
            self.connections = connections
            self.current = current
            self.providers = providers
            providerSlug = current?.provider ?? ""
            modelId = current?.model ?? ""
        }

        /// Model ids the chosen provider offers.
        var suggestedModels: [String] {
            providers.first { $0.slug == providerSlug }?.models ?? []
        }

        /// Reads the current model and the providers with credentials. Does nothing until the connection is up.
        func load() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            do {
                current = try await rest.modelInfo()
                providers = try await rest.providerCatalog().providers
                if providerSlug.isEmpty { providerSlug = current?.provider ?? "" }
                if modelId.isEmpty { modelId = current?.model ?? "" }
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Fills the model field with the server's recommendation for the chosen provider.
        func useRecommended() async {
            guard let provider = providerSlug.providerNonEmpty,
                let rest = await ProviderServer.rest(connections)
            else { return }
            do {
                let answer = try await rest.recommendedModel(provider: provider)
                if let model = answer.model?.providerNonEmpty {
                    modelId = model
                    errorText = nil
                } else {
                    errorText = "This provider has no recommended model. Pick one."
                }
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Makes the chosen provider and model the main one. New chats use it; running chats keep theirs. Status-only:
        /// the model is read again, and the message reports what the server now holds.
        func save() async {
            guard let provider = providerSlug.providerNonEmpty, let model = modelId.providerNonEmpty else {
                errorText = "Choose a provider and a model."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            let assignment = ModelDefaultsAssignment(
                scope: ModelDefaultsScopes.main, provider: provider, model: model,
                reasoningEffort: effort.providerNonEmpty)
            var failure: String?
            do {
                try await rest.assignModel(assignment)
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            current = (try? await rest.modelInfo()) ?? current
            errorText = failure
            if failure != nil {
                savedText = nil
            } else if current?.provider == provider && current?.model == model {
                savedText = "Saved. New chats use \(model)."
            } else {
                savedText = "Sent. The server still reports \(current?.model ?? "no model")."
            }
        }
    }
#endif
