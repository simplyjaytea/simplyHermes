#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Credentials pool: add a key to the pool (WP-53a).
    struct CredentialPoolScreen: View {
        @State private var model: CredentialPoolModel

        init(connections: ConnectionsModel) {
            _model = State(initialValue: CredentialPoolModel(connections: connections))
        }

        init(model: CredentialPoolModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            Form {
                Section {
                    TextField("Provider, such as openrouter", text: $model.provider)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pool.provider")
                    SecureField("API key", text: $model.apiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("pool.key")
                    TextField("Label (optional)", text: $model.label)
                } header: {
                    Text("Add a key")
                } footer: {
                    Text("The key goes to your Hermes server and is not kept on this phone.")
                }
                Section {
                    Button("Add to pool") {
                        Task { await model.add() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("pool.add")
                    if let savedText = model.savedText {
                        Text(savedText).foregroundStyle(HermesColor.secondaryText)
                    }
                } footer: {
                    Text("Showing and removing pooled keys comes later.")
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Credentials pool")
        }
    }

    #Preview("Credentials pool, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { CredentialPoolScreen(model: CredentialPoolModel(connections: .preview())) }
    }

    #Preview("Credentials pool, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { CredentialPoolScreen(model: CredentialPoolModel(connections: .preview())) }
    }

    #Preview("Credentials pool, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { CredentialPoolScreen(model: CredentialPoolModel(connections: .preview())) }
    }

    #Preview("Credentials pool, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { CredentialPoolScreen(model: CredentialPoolModel(connections: .preview())) }
    }
#endif
