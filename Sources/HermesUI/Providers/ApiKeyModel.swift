#if canImport(UIKit)
    import HermesKit
    import Observation

    /// Sets, checks, deletes and reveals provider keys in the server's env store (WP-53a).
    ///
    /// The app never reads the store on its own. Only ``reveal()`` asks for a value, and only when the user taps Reveal.
    @MainActor
    @Observable
    final class ApiKeyModel {
        var name = ""
        var value = ""
        private(set) var checkText: String?
        private(set) var statusText: String?
        private(set) var errorText: String?
        /// The value the server returned for ``reveal()``, as text. Cleared when the screen goes away.
        private(set) var revealed: String?
        private(set) var isWorking = false
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Asks the provider whether the typed key works. Nothing is saved.
        func check() async {
            guard let key = name.providerNonEmpty, let secret = value.providerNonEmpty else {
                errorText = "Enter a name and a value."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let result = try await rest.validateProviderKey(ApiKeyWrite(key: key, value: secret))
                checkText = ProviderKeyCheckText.text(for: result)
                errorText = nil
            } catch {
                checkText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Saves the typed name and value. The value field is cleared on success.
        func save() async {
            guard let key = name.providerNonEmpty, let secret = value.providerNonEmpty else {
                errorText = "Enter a name and a value."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await rest.setApiKey(ApiKeyWrite(key: key, value: secret))
                value = ""
                errorText = nil
                statusText = "Saved \(key)."
            } catch {
                statusText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Deletes the named variable. Call it only after the user confirms.
        func delete() async {
            guard let key = name.providerNonEmpty else {
                errorText = "Enter the name to delete."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await rest.deleteApiKey(named: key)
                revealed = nil
                errorText = nil
                statusText = "Deleted \(key)."
            } catch {
                statusText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Shows the stored value of the named variable. Only the Reveal button calls this.
        func reveal() async {
            guard let key = name.providerNonEmpty else {
                errorText = "Enter the name to show."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let answer = try await rest.revealApiKey(named: key)
                revealed = ProviderAnswer.text(answer)
                errorText = nil
            } catch {
                revealed = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Hides a revealed value again.
        func hideRevealed() {
            revealed = nil
        }
    }
#endif
