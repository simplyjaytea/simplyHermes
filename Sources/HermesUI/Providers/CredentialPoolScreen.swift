#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Credentials pool: the pooled keys, removal with confirmation, and a form to add a key (WP-53a).
    struct CredentialPoolScreen: View {
        @State private var model: CredentialPoolModel
        @State private var pendingRemove: CredentialPoolRemoval?

        init(connections: ConnectionsModel) {
            _model = State(initialValue: CredentialPoolModel(connections: connections))
        }

        init(model: CredentialPoolModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            CredentialPoolRow(entry: entry)
                                .swipeActions(edge: .trailing) {
                                    Button("Remove", role: .destructive) {
                                        pendingRemove = CredentialPoolRemoval(provider: group.provider, entry: entry)
                                    }
                                }
                        }
                    } header: {
                        Text(group.provider)
                    }
                }
                if model.groups.isEmpty && !model.isLoading {
                    Section {
                        Text("No pooled keys yet.").foregroundStyle(HermesColor.secondaryText)
                    }
                }
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
                    Button("Add to pool") {
                        Task { await model.add() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("pool.add")
                    if let statusText = model.statusText {
                        Text(statusText).foregroundStyle(HermesColor.secondaryText)
                    }
                } header: {
                    Text("Add a key")
                } footer: {
                    Text("The key goes to your Hermes server and is not kept on this phone.")
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Credentials pool")
            .task { await model.load() }
            .refreshable { await model.load() }
            .confirmationDialog(
                "Remove this key from the pool?", isPresented: removeIsPresented, titleVisibility: .visible
            ) {
                Button("Remove key", role: .destructive) {
                    if let removal = pendingRemove {
                        Task { await model.remove(removal.entry, provider: removal.provider) }
                    }
                    pendingRemove = nil
                }
            } message: {
                Text("The server removes the key from the pool and from where it was stored. This can't be undone.")
            }
        }

        private var removeIsPresented: Binding<Bool> {
            Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })
        }
    }

    /// A removal waiting for the user's confirmation.
    struct CredentialPoolRemoval {
        let provider: String
        let entry: CredentialPoolEntry
    }

    /// One pooled key: its label, where it came from, and how often it has served requests. The token is never shown.
    struct CredentialPoolRow: View {
        let entry: CredentialPoolEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label?.providerNonEmpty ?? "Key \(entry.index)")
                    .font(HermesFont.body.weight(.semibold))
                Text(detailText)
                    .font(HermesFont.caption)
                    .foregroundStyle(HermesColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }

        private var detailText: String {
            var parts: [String] = []
            if let source = entry.source?.providerNonEmpty { parts.append(source) }
            if let authType = entry.authType?.providerNonEmpty { parts.append(authType) }
            if let count = entry.requestCount { parts.append("\(count) requests") }
            return parts.isEmpty ? "Stored on the server" : parts.joined(separator: " · ")
        }
    }

    #Preview("Credentials pool, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { CredentialPoolScreen(model: sampleModel()) }
    }

    #Preview("Credentials pool, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { CredentialPoolScreen(model: sampleModel()) }
    }

    #Preview("Credentials pool, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { CredentialPoolScreen(model: sampleModel()) }
    }

    #Preview("Credentials pool, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { CredentialPoolScreen(model: sampleModel()) }
    }

    /// A model with sample groups and no connection, for previews.
    @MainActor
    private func sampleModel() -> CredentialPoolModel {
        CredentialPoolModel(connections: .preview(), groups: ProviderSamples.credentialPool)
    }
#endif
