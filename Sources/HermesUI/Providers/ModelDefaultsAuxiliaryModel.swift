#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The auxiliary model tasks and the effort each one runs with (WP-53a).
    @MainActor
    @Observable
    final class ModelDefaultsAuxiliaryModel {
        private(set) var tasks: [ModelDefaultsAuxiliaryTask] = []
        private(set) var main: ModelDefaultsSlot?
        private(set) var isLoading = false
        private(set) var errorText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel, tasks: [ModelDefaultsAuxiliaryTask] = [], main: ModelDefaultsSlot? = nil) {
            self.connections = connections
            self.tasks = tasks
            self.main = main
        }

        /// Reads every task row. Does nothing until the server connection is up.
        func load() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let answer = try await rest.auxiliaryModels()
                tasks = answer.tasks
                main = answer.main
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Sets the effort of one task. The row's stored provider, model and endpoint go back unchanged, so only the
        /// effort moves. Status-only: the rows are read again afterwards, and the effort shown is the one the server
        /// stores.
        func setEffort(_ effort: String, for task: ModelDefaultsAuxiliaryTask) async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            let assignment = ModelDefaultsAssignment(
                scope: ModelDefaultsScopes.auxiliary, provider: task.provider?.providerNonEmpty ?? "auto",
                model: task.model ?? "", task: task.task, reasoningEffort: effort, baseUrl: task.baseUrl ?? "")
            var failure: String?
            do {
                try await rest.assignModel(assignment)
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            if let failure { errorText = failure }
        }
    }
#endif
