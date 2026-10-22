#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import SwiftUI

    /// The toolsets of the active profile (WP-51): the list, and the switch of each one.
    @MainActor
    @Observable
    final class SkillToolsetsModel {
        private(set) var toolsets: [ToolsetInfo] = []
        private(set) var isLoading = false
        /// Why the list could not load. Nil when it loaded.
        private(set) var loadError: String?
        @ObservationIgnored private let connections: ConnectionsModel?

        init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        /// Reads the toolsets in the order the server lists them.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                toolsets = try await rest.toolsets()
                loadError = nil
            } catch {
                loadError = ToolsMessages.text(for: error)
            }
        }
    }

    /// One toolset: its switch, the provider picker, the keys of the chosen provider, and its model catalog.
    @MainActor
    @Observable
    final class ToolsetDetailModel {
        let name: String
        let title: String
        private(set) var enabled: Bool
        private(set) var config: SkillToolsetConfig?
        private(set) var models: SkillToolsetModelCatalog?
        private(set) var isLoading = false
        /// The capability the web toolset's provider applies to: `search` or `extract`.
        var webCapability = "search"
        var notice: ToolsNotice?
        let actions = ToolsActionRunner()
        @ObservationIgnored private let connections: ConnectionsModel?

        init(connections: ConnectionsModel?, toolset: ToolsetInfo) {
            self.connections = connections
            name = toolset.name
            title = toolset.label ?? toolset.name
            enabled = toolset.enabled
        }

        /// The provider the server says is in use, or nil when there is no picker.
        var activeProvider: ToolsetProviderRow? {
            config?.providers?.first { $0.isActive == true }
        }

        /// Reads the provider picker and, when the toolset has one, its model catalog.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                config = try await rest.skillToolsetConfig(name)
                let catalog = try? await rest.skillToolsetModels(name)
                models = catalog?.hasModels == true ? catalog : nil
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Turns the toolset on or off. When the switch starts an install, the server runs it in the background.
        func setEnabled(_ value: Bool) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.setSkillToolsetEnabled(name, enabled: value)
                enabled = result.enabled ?? value
                if let provider = result.postSetupStarted {
                    notice = ToolsNotice.info("Installing \(provider) on the server. Check back in a few minutes.")
                } else {
                    notice = nil
                }
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Picks the provider the toolset uses. A managed provider can need a Nous Portal sign-in first.
        func select(_ provider: ToolsetProviderRow) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let capability = name == "web" ? webCapability : nil
                let result = try await rest.selectSkillToolsetProvider(
                    name, provider: provider.name, capability: capability)
                if result.needsNousAuth == true {
                    notice = ToolsNotice.error("Sign in to Nous Portal to use \(provider.name).")
                } else {
                    notice = nil
                }
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Saves the keys that have a value. Blank fields keep what is saved. Returns true when they were saved.
        func saveKeys(_ values: [String: String]) async -> Bool {
            let filled = values.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !filled.isEmpty else {
                notice = ToolsNotice.error("Enter a key first.")
                return false
            }
            do {
                let rest = try await ToolsServer.rest(connections)
                _ = try await rest.saveSkillToolsetEnv(name, env: filled)
                notice = ToolsNotice.info("Saved on the server.")
                await load()
                return true
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
                return false
            }
        }

        /// Starts a provider's install (its post-setup key) and waits for the server.
        func runPostSetup(_ key: String) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let start = try await rest.runSkillToolsetPostSetup(name, key: key)
                let status = try await actions.run(start, title: "Installing for \(title)", rest: rest)
                notice = status.succeeded ? nil : ToolsNotice.error(ToolsMessages.failedAction)
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Picks a model from the catalog of the toolset's backend.
        func selectModel(_ option: ToolsetModelOption) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                _ = try await rest.selectSkillToolsetModel(name, model: option.id, provider: models?.provider)
                notice = nil
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }
    }

    /// Every toolset on the server, with whether it is on and set up. Tap one to configure it.
    struct ToolsetsScreen: View {
        @State private var model: SkillToolsetsModel
        private let connections: ConnectionsModel?

        /// `connections` is nil when the shell has none. The list then says that no server is connected.
        init(connections: ConnectionsModel?) {
            self.connections = connections
            _model = State(initialValue: SkillToolsetsModel(connections: connections))
        }

        var body: some View {
            List {
                if let error = model.loadError {
                    Section { ToolsNoticeRow(notice: ToolsNotice.error(error)) }
                }
                Section {
                    ForEach(model.toolsets) { toolset in
                        NavigationLink {
                            ToolsetDetailScreen(connections: connections, toolset: toolset)
                        } label: {
                            ToolsetRow(toolset: toolset)
                        }
                        .accessibilityIdentifier("toolsets.row.\(toolset.name)")
                    }
                } footer: {
                    Text("A toolset is a group of tools the agent can use. Turn one on, then set up its provider.")
                }
            }
            .navigationTitle("Toolsets")
            .onAppear { Task { await model.load() } }
            .refreshable { await model.load() }
        }
    }

    /// One toolset in the list: its name, whether it is on, and whether it needs setup.
    private struct ToolsetRow: View {
        let toolset: ToolsetInfo

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(toolset.label ?? toolset.name)
                        .font(HermesFont.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(toolset.enabled ? "On" : "Off")
                        .font(HermesFont.footnote)
                        .foregroundStyle(toolset.enabled ? HermesColor.statusConnected : HermesColor.secondaryText)
                }
                if let description = toolset.description, !description.isEmpty {
                    Text(description)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
                if toolset.configured == false {
                    Text("Needs setup")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.statusWarning)
                }
            }
        }
    }

    /// One toolset: its switch, the provider picker, the keys of the chosen provider, and its model catalog.
    struct ToolsetDetailScreen: View {
        @State private var model: ToolsetDetailModel
        @State private var keyValues: [String: String] = [:]
        @State private var confirmsPostSetup = false

        init(connections: ConnectionsModel?, toolset: ToolsetInfo) {
            _model = State(initialValue: ToolsetDetailModel(connections: connections, toolset: toolset))
        }

        var body: some View {
            List {
                if let activity = model.actions.activity {
                    Section { ToolsActivityRow(activity: activity) }
                }
                if let notice = model.notice {
                    Section { ToolsNoticeRow(notice: notice) }
                }
                Section {
                    Toggle(
                        "On",
                        isOn: Binding(
                            get: { model.enabled },
                            set: { value in Task { await model.setEnabled(value) } })
                    )
                    .accessibilityIdentifier("toolset.enabled")
                }
                if let config = model.config, config.hasCategory == true {
                    providerSection(config)
                }
                if let provider = model.activeProvider, let variables = provider.envVars, !variables.isEmpty {
                    keysSection(provider: provider, variables: variables)
                }
                if let catalog = model.models, let options = catalog.models, !options.isEmpty {
                    modelSection(catalog: catalog, options: options)
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .refreshable { await model.load() }
            .confirmationDialog(
                "Install what \(model.activeProvider?.name ?? "the provider") needs?",
                isPresented: $confirmsPostSetup,
                titleVisibility: .visible
            ) {
                if let key = model.activeProvider?.postSetup {
                    Button("Install") {
                        Task { await model.runPostSetup(key) }
                    }
                }
            } message: {
                Text("The server runs the install in the background. Its progress shows at the top of this screen.")
            }
        }

        private func providerSection(_ config: SkillToolsetConfig) -> some View {
            Section {
                if model.name == "web" {
                    Picker("Used for", selection: $model.webCapability) {
                        Text("Search").tag("search")
                        Text("Extract").tag("extract")
                    }
                    .pickerStyle(.segmented)
                }
                ForEach(config.providers ?? []) { row in
                    providerRow(row)
                }
                if let provider = model.activeProvider, provider.postSetup != nil {
                    Button("Install what \(provider.name) needs") {
                        confirmsPostSetup = true
                    }
                    .disabled(model.actions.activity != nil)
                    .accessibilityIdentifier("toolset.postSetup")
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Pick the provider this toolset uses.")
            }
        }

        private func providerRow(_ row: ToolsetProviderRow) -> some View {
            Button {
                Task { await model.select(row) }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(HermesFont.body)
                        if let tag = row.tag {
                            Text(tag)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    if let badge = row.badge {
                        Text(badge)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.accent)
                    }
                    if row.isActive == true {
                        Image(systemName: "checkmark")
                            .foregroundStyle(HermesColor.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toolset.provider.\(row.name)")
        }

        private func keysSection(provider: ToolsetProviderRow, variables: [SkillToolsetEnvVar]) -> some View {
            Section {
                ForEach(variables) { variable in
                    VStack(alignment: .leading, spacing: 4) {
                        SecureField(
                            variable.isSet == true ? "\(variable.key) (saved)" : variable.key,
                            text: keyBinding(variable.key)
                        )
                        .font(HermesFont.code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        if let address = variable.url, let link = URL(string: address) {
                            Link("Where to get it", destination: link)
                                .font(HermesFont.footnote)
                        }
                    }
                }
                Button("Save keys") {
                    Task {
                        if await model.saveKeys(keyValues) {
                            keyValues = [:]
                        }
                    }
                }
                .disabled(keyValues.values.allSatisfy { $0.isEmpty } || model.actions.activity != nil)
                .accessibilityIdentifier("toolset.saveKeys")
            } header: {
                Text("Keys for \(provider.name)")
            } footer: {
                Text("Keys stay on the server. A saved key is never shown again.")
            }
        }

        private func modelSection(catalog: SkillToolsetModelCatalog, options: [ToolsetModelOption]) -> some View {
            Section {
                ForEach(options) { option in
                    Button {
                        Task { await model.selectModel(option) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.display ?? option.id)
                                    .font(HermesFont.body)
                                if let strengths = option.strengths {
                                    Text(strengths)
                                        .font(HermesFont.footnote)
                                        .foregroundStyle(HermesColor.secondaryText)
                                }
                            }
                            Spacer(minLength: 8)
                            if option.id == catalog.current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(HermesColor.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toolset.model.\(option.id)")
                }
            } header: {
                Text("Model")
            }
        }

        private func keyBinding(_ key: String) -> Binding<String> {
            Binding(
                get: { keyValues[key] ?? "" },
                set: { keyValues[key] = $0 })
        }
    }

    #Preview("Toolsets, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { ToolsetsScreen(connections: .preview()) }
    }

    #Preview("Toolsets, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { ToolsetsScreen(connections: .preview()) }
    }

    #Preview("Toolsets, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { ToolsetsScreen(connections: .preview()) }
    }

    #Preview("Toolsets, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { ToolsetsScreen(connections: .preview()) }
    }
#endif
