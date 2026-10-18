#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The providers of the active server with their status, and its custom endpoints (WP-53a).
    @MainActor
    @Observable
    final class ProviderListModel {
        private(set) var providers: [ModelProviderOptions] = []
        private(set) var endpoints: [ProviderCustomEndpoint] = []
        private(set) var isLoading = false
        private(set) var errorText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(
            connections: ConnectionsModel, providers: [ModelProviderOptions] = [],
            endpoints: [ProviderCustomEndpoint] = []
        ) {
            self.connections = connections
            self.providers = providers
            self.endpoints = endpoints
        }

        /// Reads every provider, set up or not, and every custom endpoint. Does nothing until the connection is up.
        func refresh() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                providers = try await rest.providerCatalog(includeUnconfigured: true).providers
                endpoints = try await rest.customEndpoints().endpoints
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Makes the endpoint the provider for new chats. Status-only: the list is read again afterwards.
        func activate(_ endpoint: ProviderCustomEndpoint) async {
            await change { rest in try await rest.activateCustomEndpoint(id: endpoint.id) }
        }

        /// Removes the endpoint. Call it only after the user confirms. Status-only: the list is read again afterwards.
        func delete(_ endpoint: ProviderCustomEndpoint) async {
            await change { rest in try await rest.deleteCustomEndpoint(id: endpoint.id) }
        }

        /// Runs one write, then reads the list again, so the screen shows what the server now holds.
        private func change(_ write: (RESTClient) async throws -> Void) async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            var failure: String?
            do {
                try await write(rest)
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await refresh()
            if let failure { errorText = failure }
        }
    }
#endif
