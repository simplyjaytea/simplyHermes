#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The auxiliary model tasks and the effort each one runs with (WP-53a).
    @MainActor
    @Observable
    final class ModelDefaultsAuxiliaryModel {
        private(set) var tasks: [ModelDefaultsAuxiliaryTask] = []
        private(set) var main: ModelDefaultsSlot?
        /// Efforts this screen set during this visit. The server's answer does not report the stored effort.
        private(set) var setEfforts: [String: String] = [:]
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
        /// effort moves.
        func setEffort(_ effort: String, for task: ModelDefaultsAuxiliaryTask) async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            let assignment = ModelDefaultsAssignment(
                scope: .auxiliary, provider: task.provider?.providerNonEmpty ?? "auto",
                model: task.model ?? "", task: task.task, reasoningEffort: effort, baseUrl: task.baseUrl ?? "")
            do {
                try await rest.assignModel(assignment)
                setEfforts[task.task] = effort
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }
    }
#endif
