#if canImport(UIKit)
    import HermesKit
    import Observation

    /// The credentials pool: the pooled keys, a form that adds one, and removal (WP-53a).
    @MainActor
    @Observable
    final class CredentialPoolModel {
        var provider = ""
        var apiKey = ""
        var label = ""
        private(set) var groups: [CredentialPoolProvider] = []
        private(set) var isLoading = false
        private(set) var isWorking = false
        private(set) var errorText: String?
        private(set) var statusText: String?
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel, groups: [CredentialPoolProvider] = []) {
            self.connections = connections
            self.groups = groups
        }

        /// Reads the pool. Does nothing until the server connection is up.
        func load() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                groups = try await rest.credentialPool().providers
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Adds the key to the pool, then reads the pool again. The key field is cleared on success.
        func add() async {
            guard let slug = provider.providerNonEmpty, let key = apiKey.providerNonEmpty else {
                errorText = "Enter a provider and a key."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            let draft = CredentialPoolDraft(provider: slug, apiKey: key, label: label.providerNonEmpty)
            var failure: String?
            do {
                try await rest.addCredential(draft)
                apiKey = ""
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            errorText = failure ?? errorText
            statusText = failure == nil ? "Added to the pool for \(slug)." : nil
        }

        /// Removes one pooled key, then reads the pool again, so the status says whether the key is still listed. Call
        /// it only after the user confirms.
        func remove(_ entry: CredentialPoolEntry, provider slug: String) async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            var failure: String?
            do {
                try await rest.removeCredential(provider: slug, index: entry.index)
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            errorText = failure ?? errorText
            if failure != nil || errorText != nil {
                statusText = nil
            } else if groups.contains(where: { group in group.entries.contains { $0.id == entry.id } }) {
                statusText = "The pool still lists this key."
            } else {
                statusText = "Removed from the pool."
            }
        }
    }
#endif
