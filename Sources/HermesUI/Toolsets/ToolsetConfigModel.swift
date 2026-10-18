#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The settings of one toolset: the provider in use, the keys each provider reads, and a media backend's model
    /// (WP-53b).
    ///
    /// Every change goes to the server, then the settings are read again. Blank keys are never sent, so a blank field
    /// keeps the stored key.
    @MainActor
    @Observable
    public final class ToolsetConfigModel {
        /// Toolset name, as the server knows it.
        public let name: String
        /// Name to show.
        public let title: String
        public private(set) var config: ToolsetConfig?
        /// The models of the active provider, when it has a list.
        public private(set) var models: ToolsetModelCatalog?
        public private(set) var isLoading = false
        /// True while a choice, a save or a setup is being sent.
        public private(set) var isSaving = false
        public private(set) var errorText: String?
        /// Set after a change that needs a word: a background setup, or a provider the app cannot activate.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `config` and `models` seed the screen, for previews.
        public init(
            connections: ConnectionsModel, name: String, title: String, config: ToolsetConfig? = nil,
            models: ToolsetModelCatalog? = nil
        ) {
            self.connections = connections
            self.name = name
            self.title = title
            self.config = config
            self.models = models
        }

        /// Reads the settings. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                try await load(rest)
                errorText = nil
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Chooses a provider row. `capability` (`search` or `extract`) applies to the web toolset only; nil sets both.
        public func selectProvider(_ provider: String, capability: String?) async {
            let toolset = name
            await change { rest in
                let result = try await rest.selectToolsetProvider(toolset, provider: provider, capability: capability)
                guard result.needsNousAuth == true else { return nil }
                return "\(provider) needs a Nous Portal subscription, which this app can't sign in to. "
                    + "It is not active."
            }
        }

        /// Chooses a model of the media backend.
        public func selectModel(_ model: String) async {
            let toolset = name
            let provider = models?.provider
            await change { rest in
                try await rest.selectToolsetModel(toolset, model: model, provider: provider)
                return nil
            }
        }

        /// Starts a provider's install on the server, in the background.
        public func runSetup(_ provider: ToolsetProvider) async {
            guard let key = provider.postSetup else { return }
            let toolset = name
            await change { rest in
                try await rest.runToolsetPostSetup(toolset, key: key)
                return "Setting up \(provider.name) in the background. This screen doesn't follow its progress."
            }
        }

        /// Stores the keys the user typed. A blank value is left out, so the stored key stays. Returns true when the
        /// server saved them.
        public func saveKeys(_ values: [String: String]) async -> Bool {
            let filled = values.compactMapValues { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard !filled.isEmpty else { return false }
            let toolset = name
            await change { rest in
                _ = try await rest.saveToolsetEnv(toolset, env: filled)
                return nil
            }
            return errorText == nil
        }

        /// Runs one change, then reads the settings again. `action` returns a notice to show, or nil.
        private func change(_ action: (RESTClient) async throws -> String?) async {
            isSaving = true
            defer { isSaving = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                notice = try await action(rest)
                errorText = nil
                try await load(rest)
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }

        /// Reads the settings, and the model list of the active provider. A failed model list leaves the list out
        /// instead of failing the whole screen.
        private func load(_ rest: RESTClient) async throws {
            config = try await rest.toolsetConfig(name)
            models = try? await rest.toolsetModels(name)
        }
    }

    extension ToolsetConfigModel {
        /// A model with sample settings, for previews. `media` shows a media backend's model list instead of providers.
        /// It never reaches a server.
        static func preview(media: Bool = false) -> ToolsetConfigModel {
            if media {
                return ToolsetConfigModel(
                    connections: .preview(), name: "image_gen", title: "Image Generation",
                    models: ToolsetAdminSamples.toolsetModels)
            }
            return ToolsetConfigModel(
                connections: .preview(), name: "web", title: "Web Search & Scraping",
                config: ToolsetAdminSamples.toolsetConfig)
        }
    }
#endif
