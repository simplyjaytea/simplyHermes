#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The form behind "Add custom endpoint": validates the endpoint against its `/models` URL, then saves it (WP-53a).
    @MainActor
    @Observable
    final class ProviderCustomEndpointModel: Identifiable {
        let id = UUID()
        var name = ""
        var baseUrl = ""
        var modelId = ""
        var apiKey = ""
        /// One of ``ProviderAPIModes``. Nil is automatic.
        var apiMode: String?
        var contextLengthText = ""
        var discoverModels = true
        var makeDefault = false
        private(set) var validationText: String?
        private(set) var isWorking = false
        private(set) var errorText: String?
        /// Set once the endpoint is saved, so the sheet can close.
        private(set) var didSave = false
        @ObservationIgnored let connections: ConnectionsModel

        init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Name, base URL and model are needed before the endpoint can be checked or saved.
        var canSubmit: Bool {
            !name.providerTrimmed.isEmpty && !baseUrl.providerTrimmed.isEmpty && !modelId.providerTrimmed.isEmpty
        }

        /// Probes the endpoint's model list with the form's values. Nothing is saved.
        func validate() async {
            guard let draft = currentDraft(), let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                validationText = ProviderAnswer.text(try await rest.validateCustomEndpoint(draft), limit: 600)
                errorText = nil
            } catch {
                validationText = nil
                errorText = ProviderErrorText.message(for: error)
            }
        }

        /// Saves the endpoint. With "Use as default" on, it also becomes the provider for new chats. Status-only: the
        /// list is read again by the screen when the sheet closes.
        func save() async {
            guard let draft = currentDraft(), let rest = await ProviderServer.rest(connections) else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await rest.saveCustomEndpoint(draft)
                apiKey = ""
                didSave = true
                errorText = nil
            } catch {
                errorText = ProviderErrorText.message(for: error)
            }
        }

        private func currentDraft() -> ProviderCustomEndpointDraft? {
            guard canSubmit else {
                errorText = "Name, base URL and model are needed."
                return nil
            }
            var contextLength: Int?
            if let text = contextLengthText.providerNonEmpty {
                guard let value = Int(text), value > 0 else {
                    errorText = "Context length must be a whole number of tokens."
                    return nil
                }
                contextLength = value
            }
            return ProviderCustomEndpointDraft(
                name: name.providerTrimmed, baseUrl: baseUrl.providerTrimmed, model: modelId.providerTrimmed,
                apiKey: apiKey.providerNonEmpty, apiMode: apiMode, contextLength: contextLength,
                discoverModels: discoverModels, makeDefault: makeDefault ? true : nil)
        }
    }
#endif
