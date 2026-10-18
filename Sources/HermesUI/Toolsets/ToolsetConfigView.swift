#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One toolset's settings: the provider in use, the keys each provider reads, and the backends the web toolset uses
    /// for search and extract (WP-53b). The model picker is not on this screen.
    ///
    /// Keys go into secure fields and are sent once. The server stores them and never returns them, so the screen shows
    /// only whether each key is saved.
    public struct ToolsetConfigView: View {
        private let connections: ConnectionsModel
        @State private var model: ToolsetConfigModel
        @State private var keyValues: [String: String] = [:]
        @State private var webCapability = WebCapability.both

        public init(connections: ConnectionsModel, toolset: ToolsetInfo) {
            self.connections = connections
            _model = State(
                initialValue: ToolsetConfigModel(
                    connections: connections, name: toolset.name, title: toolset.label ?? toolset.name))
        }

        init(connections: ConnectionsModel, model: ToolsetConfigModel) {
            self.connections = connections
            _model = State(initialValue: model)
        }

        public var body: some View {
            Form {
                if let notice = model.notice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
                if let config = model.config {
                    backendSection(config)
                    providerSections(config)
                    keySections(config)
                    if (config.providers ?? []).isEmpty {
                        Section {
                            Text("This toolset has no settings to change here.")
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                }
            }
            .navigationTitle(model.title)
            .overlay {
                if model.config == nil && model.isLoading {
                    ProgressView()
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }

        /// The backends the web toolset uses now. Shown only when the server reports one.
        @ViewBuilder
        private func backendSection(_ config: ToolsetConfig) -> some View {
            if config.activeSearchBackend != nil || config.activeExtractBackend != nil {
                Section {
                    LabeledContent {
                        Text(config.activeSearchBackend ?? "None")
                    } label: {
                        Text("Search")
                    }
                    LabeledContent {
                        Text(config.activeExtractBackend ?? "None")
                    } label: {
                        Text("Extract")
                    }
                } header: {
                    Text("In use")
                }
            }
        }

        @ViewBuilder
        private func providerSections(_ config: ToolsetConfig) -> some View {
            let providers = config.providers ?? []
            if !providers.isEmpty {
                Section {
                    Picker("Provider", selection: providerBinding(providers)) {
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.name)
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("toolset.provider")
                    if providers.contains(where: { !($0.capabilities ?? []).isEmpty }) {
                        Picker("Use for", selection: $webCapability) {
                            Text("Search and extract").tag(WebCapability.both)
                            Text("Search").tag(WebCapability.search)
                            Text("Extract").tag(WebCapability.extract)
                        }
                        .disabled(model.isSaving)
                    }
                    ForEach(providers.filter { $0.requiresNousAuth == true }) { provider in
                        Text("\(provider.name) needs a Nous Portal subscription. This app can't sign in to it.")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    Text(statusSentence(providers))
                }
                setupSection(providers)
            }
        }

        @ViewBuilder
        private func setupSection(_ providers: [ToolsetProvider]) -> some View {
            let needed = providers.filter { $0.postSetup != nil && $0.status != "ready" }
            if !needed.isEmpty {
                Section {
                    ForEach(needed) { provider in
                        Button("Set up \(provider.name)", systemImage: "arrow.down.circle") {
                            Task { await model.runSetup(provider) }
                        }
                        .disabled(model.isSaving)
                    }
                } footer: {
                    Text("Setup runs on the Hermes server in the background. This screen doesn't follow its progress.")
                }
            }
        }

        @ViewBuilder
        private func keySections(_ config: ToolsetConfig) -> some View {
            let variables = Self.uniqueVariables(config)
            if !variables.isEmpty {
                Section {
                    ForEach(variables) { variable in
                        keyRow(variable)
                    }
                    Button("Save keys", systemImage: "key") { saveKeys() }
                        .disabled(model.isSaving || !hasTypedKeys)
                        .accessibilityIdentifier("toolset.saveKeys")
                } header: {
                    Text("Keys")
                } footer: {
                    Text("Keys are saved in the server's .env file. A blank field keeps the saved key.")
                }
            }
        }

        private func keyRow(_ variable: ToolsetEnvVar) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                SecureField(variable.prompt ?? variable.key, text: keyBinding(variable.key))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("toolset.key.\(variable.key)")
                HStack(spacing: 8) {
                    Text(variable.isSet == true ? "Saved" : "Not set")
                        .font(HermesFont.caption)
                        .foregroundStyle(
                            variable.isSet == true ? HermesColor.statusConnected : HermesColor.secondaryText)
                    Spacer(minLength: 8)
                    if let link = variable.url.flatMap({ URL(string: $0) }) {
                        Link("Get a key", destination: link)
                            .font(HermesFont.caption)
                    }
                }
            }
        }

        /// The provider in use, and a choice of another one. The server's answer is only checked for its status.
        private func providerBinding(_ providers: [ToolsetProvider]) -> Binding<String> {
            let active = providers.first(where: { $0.isActive == true })?.name ?? ""
            return Binding(
                get: { active },
                set: { name in
                    guard name != active else { return }
                    let capability = webCapability.value
                    Task { await model.selectProvider(name, capability: capability) }
                })
        }

        private func keyBinding(_ key: String) -> Binding<String> {
            Binding(get: { keyValues[key] ?? "" }, set: { keyValues[key] = $0 })
        }

        private var hasTypedKeys: Bool {
            keyValues.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        private func saveKeys() {
            let values = keyValues
            Task {
                if await model.saveKeys(values) {
                    keyValues = [:]
                }
            }
        }

        /// One sentence about the provider in use, from its status.
        private func statusSentence(_ providers: [ToolsetProvider]) -> String {
            guard let active = providers.first(where: { $0.isActive == true }) else {
                return "No provider is in use."
            }
            switch active.status ?? "" {
            case "ready": return "\(active.name) is ready to use."
            case "needs_keys": return "\(active.name) needs a key. Add it under Keys."
            case "needs_auth": return "\(active.name) needs a sign-in."
            case "needs_setup": return "\(active.name) needs setup. Use Set up below."
            default: return "Provider in use: \(active.name)."
            }
        }

        /// The keys of every provider, each once, in the server's order.
        private static func uniqueVariables(_ config: ToolsetConfig) -> [ToolsetEnvVar] {
            var seen = Set<String>()
            let all = (config.providers ?? []).flatMap { $0.envVars ?? [] }
            return all.filter { seen.insert($0.key).inserted }
        }
    }

    /// Which web capability a provider choice applies to. `both` sends no capability, so the server sets both.
    private enum WebCapability: Hashable {
        case both
        case search
        case extract

        var value: String? {
            switch self {
            case .both: nil
            case .search: "search"
            case .extract: "extract"
            }
        }
    }

    #Preview("Toolset settings, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ToolsetConfigView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolset settings, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ToolsetConfigView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolset settings, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ToolsetConfigView(connections: .preview(), model: .preview()) }
    }

    #Preview("Toolset settings, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ToolsetConfigView(connections: .preview(), model: .preview()) }
    }
#endif
