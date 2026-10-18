#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > API keys: set, check, reveal and delete provider keys on the server (WP-53a).
    struct ApiKeyScreen: View {
        @State private var model: ApiKeyModel
        @State private var showsDeleteConfirm = false

        init(connections: ConnectionsModel) {
            _model = State(initialValue: ApiKeyModel(connections: connections))
        }

        init(model: ApiKeyModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            Form {
                Section {
                    TextField("Name, such as OPENROUTER_API_KEY", text: $model.name)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("keys.name")
                    SecureField("Value", text: $model.value)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("keys.value")
                } header: {
                    Text("Key")
                } footer: {
                    Text("Values go to your Hermes server. They are not kept on this phone.")
                }
                Section {
                    Button("Check with the provider") {
                        Task { await model.check() }
                    }
                    .disabled(model.isWorking)
                    if let checkText = model.checkText {
                        Text(checkText).foregroundStyle(HermesColor.secondaryText)
                    }
                    Button("Save") {
                        Task { await model.save() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("keys.save")
                    if let statusText = model.statusText {
                        Text(statusText).foregroundStyle(HermesColor.secondaryText)
                    }
                }
                Section {
                    Button("Show value") {
                        Task { await model.reveal() }
                    }
                    .disabled(model.isWorking)
                    if let revealed = model.revealed {
                        Text(revealed)
                            .font(HermesFont.codeSmall)
                            .textSelection(.enabled)
                        Button("Hide value") { model.hideRevealed() }
                    }
                } header: {
                    Text("Show")
                } footer: {
                    Text("The server limits how often a value can be shown.")
                }
                Section {
                    Button("Delete key", role: .destructive) {
                        showsDeleteConfirm = true
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("keys.delete")
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("API keys")
            .onDisappear { model.hideRevealed() }
            .confirmationDialog("Delete this key?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
                Button("Delete key", role: .destructive) {
                    Task { await model.delete() }
                }
            } message: {
                Text("The variable is removed from the server. This can't be undone.")
            }
        }
    }

    #Preview("API keys, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ApiKeyScreen(model: ApiKeyModel(connections: .preview())) }
    }

    #Preview("API keys, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ApiKeyScreen(model: ApiKeyModel(connections: .preview())) }
    }

    #Preview("API keys, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ApiKeyScreen(model: ApiKeyModel(connections: .preview())) }
    }

    #Preview("API keys, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ApiKeyScreen(model: ApiKeyModel(connections: .preview())) }
    }
#endif
