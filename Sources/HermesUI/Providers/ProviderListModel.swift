#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The providers of the active server with their status: set up or not, and the one in use (WP-53a).
    @MainActor
    @Observable
    final class ProviderListModel {
        private(set) var providers: [ModelProviderOptions] = []
        private(set) var isLoading = false
        private(set) var errorText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel, providers: [ModelProviderOptions] = []) {
            self.connections = connections
            self.providers = providers
        }

        /// Reads every provider, set up or not. Does nothing until the server connection is up.
        func refresh() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                providers = try await rest.providerCatalog(includeUnconfigured: true).providers
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }
    }
#endif
