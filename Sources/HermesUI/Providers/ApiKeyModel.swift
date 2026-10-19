#if canImport(UIKit)
    import HermesKit
    import Observation

    /// Sets, checks, deletes and reveals provider keys in the server's env store (WP-53a).
    ///
    /// The list shows only the names of variables that are set. Values are never read on load: only ``reveal()`` asks
    /// for one, and only when the user taps Show value.
    @MainActor
    @Observable
    final class ApiKeyModel {
        var name = ""
        var value = ""
        /// Names of the variables that have a value on the server, sorted.
        private(set) var setNames: [String] = []
        private(set) var checkText: String?
        private(set) var statusText: String?
        private(set) var errorText: String?
        /// The value the server returned for ``reveal()``, as text. Cleared when the screen goes away.
        private(set) var revealed: String?
        private(set) var isWorking = false
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel, setNames: [String] = []) {
            self.connections = connections
            self.setNames = setNames
        }

        /// Reads the variables and keeps the names of those that are set. Does nothing until the connection is up.
        func load() async {
            guard let rest = await ProviderServer.rest(connections) else { return }
            do {
                let env = try await rest.envVars()
                setNames = env.filter { $0.value.isSet == true }.map { $0.key }.sorted()
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Fills the form from a name in the list. It reveals nothing.
        func pick(_ key: String) {
            name = key
            value = ""
            revealed = nil
        }

        /// Sends the typed key to the provider check. The check is status-only: its answer is not read, so the screen
        /// claims nothing about the key. Nothing is saved.
        func check() async {
            guard let key = name.providerNonEmpty, let secret = value.providerNonEmpty else {
                errorText = "Enter a name and a value."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await rest.validateProviderKey(ApiKeyWrite(key: key, value: secret))
                checkText = "Check sent. The provider's answer is not shown yet."
                errorText = nil
            } catch {
                checkText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Saves the typed name and value, then reads the list again. The value field is cleared on success.
        func save() async {
            guard let key = name.providerNonEmpty, let secret = value.providerNonEmpty else {
                errorText = "Enter a name and a value."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            var failure: String?
            do {
                try await rest.setApiKey(ApiKeyWrite(key: key, value: secret))
                value = ""
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            errorText = failure ?? errorText
            if failure == nil {
                statusText = setNames.contains(key) ? "Saved \(key)." : "The server does not report \(key) as set."
            } else {
                statusText = nil
            }
        }

        /// Deletes the named variable, then reads the list again. Call it only after the user confirms.
        func delete() async {
            guard let key = name.providerNonEmpty else {
                errorText = "Enter the name to delete."
                return
            }
            guard let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            var failure: String?
            do {
                try await rest.deleteApiKey(named: key)
                revealed = nil
            } catch {
                failure = ProviderErrorText.message(for: error)
            }
            await load()
            errorText = failure ?? errorText
            if failure == nil {
                statusText = setNames.contains(key) ? "The server still reports \(key) as set." : "Deleted \(key)."
            } else {
                statusText = nil
            }
        }

        /// Shows the stored value of the named variable. Only the Show value button calls this.
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
