#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The form that adds a key to the credentials pool (WP-53a).
    @MainActor
    @Observable
    final class CredentialPoolModel {
        var provider = ""
        var apiKey = ""
        var label = ""
        private(set) var isWorking = false
        private(set) var errorText: String?
        private(set) var savedText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Adds the key to the pool. The key field is cleared on success.
        func add() async {
            guard let slug = provider.providerNonEmpty, let key = apiKey.providerNonEmpty else {
                errorText = "Enter a provider and a key."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            let draft = CredentialPoolDraft(provider: slug, apiKey: key, label: label.providerNonEmpty)
            do {
                _ = try await rest.addCredential(draft)
                apiKey = ""
                errorText = nil
                savedText = "Added to the pool for \(slug)."
            } catch {
                savedText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }
    }
#endif
