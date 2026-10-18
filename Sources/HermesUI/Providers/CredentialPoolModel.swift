#if canImport(UIKit)
    import HermesKit
    import Observation

    /// A pooled key the user asked to remove, as the pool listed it when the user asked. The confirmation shows these
    /// values.
    struct CredentialPoolRemoval: Equatable {
        let provider: String
        let id: String
        let label: String?
        let index: Int

        /// The label to show, or a plain fallback when the key has none.
        var shownLabel: String { label?.providerNonEmpty ?? "no label" }
    }

    /// The credentials pool: the pooled keys, a form that adds one, and removal (WP-53a).
    ///
    /// Removal reads the pool twice. Asking reads it so the confirmation shows what the server lists. Confirming reads
    /// it again and takes the index from that read; if the entry is gone or its index moved, nothing is removed.
    @MainActor
    @Observable
    final class CredentialPoolModel {
        var provider = ""
        var apiKey = ""
        var label = ""
        private(set) var groups: [CredentialPoolProvider] = []
        /// The removal the confirmation is asking about. Nil when none is pending.
        private(set) var pendingRemoval: CredentialPoolRemoval?
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

        /// Reads the pool, then asks for confirmation with the provider, label and index the server lists now.
        /// Nothing is removed here. If the entry is no longer listed, no confirmation opens.
        func askToRemove(_ entry: CredentialPoolEntry, provider slug: String) async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            statusText = nil
            do {
                let listing = try await rest.credentialPool()
                groups = listing.providers
                errorText = nil
                guard let current = listing.entry(id: entry.id, provider: slug) else {
                    pendingRemoval = nil
                    errorText = "That key is no longer in the pool. The list is up to date."
                    return
                }
                pendingRemoval = CredentialPoolRemoval(
                    provider: slug, id: current.id, label: current.label, index: current.index)
            } catch {
                pendingRemoval = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Closes the confirmation without removing anything.
        func cancelRemoval() {
            pendingRemoval = nil
        }

        /// Removes the key the confirmation showed. The view passes in that removal, taken before the dialog closes.
        /// The pool is read once more and the index comes from that read. Nothing is removed if the entry is gone or
        /// its index differs from the one the user saw. Status-only: the pool is read again afterwards.
        func confirmRemoval(_ pending: CredentialPoolRemoval) async {
            pendingRemoval = nil
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            var failure: String?
            do {
                let listing = try await rest.credentialPool()
                groups = listing.providers
                let entry = listing.entry(id: pending.id, provider: pending.provider)
                if let current = entry, current.index == pending.index {
                    try await rest.removeCredential(provider: pending.provider, index: current.index)
                } else {
                    failure = "The pool changed since you asked. Nothing was removed. Ask again to see the list."
                }
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            errorText = failure ?? errorText
            if failure != nil || errorText != nil {
                statusText = nil
            } else if groups.contains(where: { group in
                group.provider == pending.provider && group.entries.contains { $0.id == pending.id }
            }) {
                statusText = "The pool still lists this key."
            } else {
                statusText = "Removed from the pool."
            }
        }
    }
#endif
