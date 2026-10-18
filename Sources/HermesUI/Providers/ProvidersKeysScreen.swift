#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Providers & keys: every provider with its status, and the custom endpoints (WP-53a).
    struct ProvidersKeysScreen: View {
        @State private var model: ProviderListModel
        @State private var endpointForm: ProviderCustomEndpointModel?
        @State private var pendingDelete: ProviderCustomEndpoint?

        init(connections: ConnectionsModel) {
            _model = State(initialValue: ProviderListModel(connections: connections))
        }

        init(model: ProviderListModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                Section {
                    ForEach(model.providers) { provider in
                        ProviderRow(provider: provider)
                    }
                } header: {
                    Text("Providers")
                } footer: {
                    Text("Set up means this server has a key or a sign-in for the provider.")
                }
                Section {
                    ForEach(model.endpoints) { endpoint in
                        ProviderEndpointRow(endpoint: endpoint)
                            .swipeActions(edge: .leading) {
                                if endpoint.isCurrent != true {
                                    Button("Use") {
                                        Task { await model.activate(endpoint) }
                                    }
                                    .tint(HermesColor.accent)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    pendingDelete = endpoint
                                }
                            }
                    }
                    Button {
                        endpointForm = ProviderCustomEndpointModel(connections: model.connections)
                    } label: {
                        Label("Add custom endpoint", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("providers.addEndpoint")
                } header: {
                    Text("Custom endpoints")
                } footer: {
                    Text(
                        "An OpenAI-compatible server you run yourself. Validate it before you save. "
                            + "Swipe a row to use or delete it."
                    )
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Providers & keys")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .sheet(item: $endpointForm, onDismiss: refreshAfterEndpoint) { form in
                ProviderCustomEndpointSheet(form: form)
            }
            .confirmationDialog(
                "Delete this endpoint?", isPresented: deleteIsPresented, titleVisibility: .visible
            ) {
                Button("Delete endpoint", role: .destructive) {
                    if let endpoint = pendingDelete {
                        Task { await model.delete(endpoint) }
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("The endpoint is removed from the server. This can't be undone.")
            }
        }

        private var deleteIsPresented: Binding<Bool> {
            Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        }

        private func refreshAfterEndpoint() {
            Task { await model.refresh() }
        }
    }

    /// One provider: its name, slug, whether it is set up, and a check when it is the one in use.
    struct ProviderRow: View {
        let provider: ModelProviderOptions

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name).font(HermesFont.body.weight(.semibold))
                    Text(provider.slug)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                    Label(setUpText, systemImage: "circle.fill")
                        .font(HermesFont.caption)
                        .foregroundStyle(setUpColor)
                }
                Spacer(minLength: 8)
                if provider.isCurrent == true {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HermesColor.accent)
                        .accessibilityLabel(Text("In use"))
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var setUpText: String {
            provider.authenticated == true ? "Set up" : "Not set up"
        }

        private var setUpColor: Color {
            provider.authenticated == true ? HermesColor.statusConnected : HermesColor.statusOffline
        }
    }

    /// One custom endpoint: its name, address and model, with a mark when it is in use. The API key is never shown.
    struct ProviderEndpointRow: View {
        let endpoint: ProviderCustomEndpoint

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.name).font(HermesFont.body.weight(.semibold))
                    Text(endpoint.baseUrl)
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                    Text(detailText)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Spacer(minLength: 8)
                if endpoint.isCurrent == true {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HermesColor.accent)
                        .accessibilityLabel(Text("In use"))
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var detailText: String {
            var parts: [String] = []
            if let model = endpoint.model?.providerNonEmpty { parts.append(model) }
            parts.append(endpoint.hasApiKey == true ? "Key saved" : "No key")
            return parts.joined(separator: " · ")
        }
    }

    #Preview("Providers & keys, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ProvidersKeysScreen(model: sampleModel())
        }
    }

    #Preview("Providers & keys, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ProvidersKeysScreen(model: sampleModel())
        }
    }

    #Preview("Providers & keys, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ProvidersKeysScreen(model: sampleModel())
        }
    }

    #Preview("Providers & keys, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ProvidersKeysScreen(model: sampleModel())
        }
    }

    /// A list with sample answers and no connection, for previews.
    @MainActor
    private func sampleModel() -> ProviderListModel {
        ProviderListModel(
            connections: .preview(), providers: ProviderSamples.providers, endpoints: ProviderSamples.customEndpoints)
    }
#endif
