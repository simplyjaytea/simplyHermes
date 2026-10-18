#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The settings of one toolset: the provider in use, and the keys each provider reads (WP-53b). The model picker is
    /// not on this screen.
    ///
    /// Every change goes to the server and is only checked for its status, then the settings are read again. Blank keys
    /// are never sent, so a blank field keeps the stored key.
    @MainActor
    @Observable
    public final class ToolsetConfigModel {
        /// Toolset name, as the server knows it.
        public let name: String
        /// Name to show.
        public let title: String
        public private(set) var config: ToolsetConfig?
        public private(set) var isLoading = false
        /// True while a choice, a save or a setup is being sent.
        public private(set) var isSaving = false
        public private(set) var errorText: String?
        /// Set after a setup the server accepted. The setup runs in the background, and this screen does not follow it.
        public private(set) var notice: String?
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates a model. `config` seeds the screen, for previews.
        public init(connections: ConnectionsModel, name: String, title: String, config: ToolsetConfig? = nil) {
            self.connections = connections
            self.name = name
            self.title = title
            self.config = config
        }

        /// Reads the settings. Does nothing until a server is set up and connected.
        public func refresh() async {
            guard connections.active != nil, connections.manager != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsetAdminClient.rest(connections)
                config = try await rest.toolsetConfig(name)
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
                try await rest.selectToolsetProvider(toolset, provider: provider, capability: capability)
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
        /// server accepted them.
        public func saveKeys(_ values: [String: String]) async -> Bool {
            let filled = values.compactMapValues { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard !filled.isEmpty else { return false }
            let toolset = name
            await change { rest in
                try await rest.saveToolsetEnv(toolset, env: filled)
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
                config = try await rest.toolsetConfig(name)
            } catch is CancellationError {
                return
            } catch {
                errorText = ToolsetAdminClient.message(for: error)
            }
        }
    }

    extension ToolsetConfigModel {
        /// A model with sample settings, for previews. It never reaches a server.
        static func preview() -> ToolsetConfigModel {
            ToolsetConfigModel(
                connections: .preview(), name: "web", title: "Web Search & Scraping",
                config: ToolsetAdminSamples.toolsetConfig)
        }
    }
#endif
