#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Models > Providers & keys: every provider with its status, and custom endpoints (WP-53a).
    struct ProvidersKeysScreen: View {
        @State private var model: ProviderListModel
        @State private var endpointForm: ProviderCustomEndpointModel?

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
                    Button {
                        endpointForm = ProviderCustomEndpointModel(connections: model.connections)
                    } label: {
                        Label("Add custom endpoint", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("providers.addEndpoint")
                } footer: {
                    Text("An OpenAI-compatible server you run yourself. Validate it before you save.")
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

    #Preview("Providers & keys, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ProvidersKeysScreen(model: ProviderListModel(connections: .preview(), providers: ProviderSamples.providers))
        }
    }

    #Preview("Providers & keys, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ProvidersKeysScreen(model: ProviderListModel(connections: .preview(), providers: ProviderSamples.providers))
        }
    }

    #Preview("Providers & keys, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ProvidersKeysScreen(model: ProviderListModel(connections: .preview(), providers: ProviderSamples.providers))
        }
    }

    #Preview("Providers & keys, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ProvidersKeysScreen(model: ProviderListModel(connections: .preview(), providers: ProviderSamples.providers))
        }
    }
#endif
