#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import SwiftUI

    /// An update that would widen what a plugin may do. Nothing changes until the user accepts the lines it adds.
    struct PendingPluginUpdate: Equatable {
        let name: String
        let lines: [String]
    }

    /// The agent plugins on the server (WP-51): the installed ones with their switch, the curated catalog, and installs
    /// from git or the catalog. The plugin calls answer at once, so this model waits for each answer.
    @MainActor
    @Observable
    final class AgentPluginsModel {
        private(set) var plugins: [AgentPlugin] = []
        private(set) var catalog: [AgentPluginCatalogEntry] = []
        /// Catalog entries the kill list withdrew, with the reason.
        private(set) var withdrawn: [AgentPluginRemoved] = []
        private(set) var isLoading = false
        /// Why the installed list could not load. Nil when it loaded.
        private(set) var loadError: String?
        /// The plugin being changed now, so its row can show progress.
        private(set) var busy: String?
        var notice: ToolsNotice?
        /// An update that waits for the user to accept what it adds.
        var pendingUpdate: PendingPluginUpdate?
        @ObservationIgnored private let connections: ConnectionsModel?

        init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        /// Reads the installed plugins, then the catalog. A catalog that cannot load leaves the installed list up.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                plugins = try await rest.agentPluginHub().plugins
                loadError = nil
                if let answer = try? await rest.agentPluginCatalog() {
                    catalog = answer.entries
                    withdrawn = answer.removed ?? []
                }
            } catch {
                loadError = ToolsMessages.text(for: error)
            }
        }

        /// Turns a plugin on or off. The gateway may need a restart before the change takes effect.
        func setEnabled(_ plugin: AgentPlugin, enabled: Bool) async {
            busy = plugin.name
            defer { busy = nil }
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.setAgentPluginEnabled(plugin.name, enabled: enabled)
                if result.restartRequired == true {
                    notice = ToolsNotice.info("Restart the gateway to apply this change.")
                } else {
                    notice = nil
                }
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Pulls a git install, or moves a catalog install to its new pin. An update that widens the plugin's
        /// capabilities stops at `pendingUpdate` until the user accepts it.
        func update(_ name: String, accept: Bool = false) async {
            busy = name
            defer { busy = nil }
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.updateAgentPlugin(name, acceptCapabilities: accept)
                if result.consentRequired == true {
                    pendingUpdate = PendingPluginUpdate(name: name, lines: result.deltaLines ?? [])
                    return
                }
                if result.ok == false {
                    notice = ToolsNotice.error(result.error ?? ToolsMessages.failedAction)
                } else if result.unchanged == true {
                    notice = ToolsNotice.info("\(name) is already up to date.")
                } else {
                    notice = nil
                }
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Deletes a user or git install. Bundled plugins cannot be removed, so the screen does not offer it.
        func remove(_ name: String) async {
            busy = name
            defer { busy = nil }
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.removeAgentPlugin(name)
                if result.ok == false {
                    notice = ToolsNotice.error(result.error ?? ToolsMessages.failedAction)
                } else {
                    notice = nil
                }
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Rereads the plugin folders on the server.
        func rescan() async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let answer = try await rest.rescanAgentPlugins()
                notice = ToolsNotice.info("Found \(answer.count ?? 0) plugins.")
                await load()
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Installs from a git URL or a catalog entry. Returns true when the server installed it.
        func install(_ request: AgentPluginInstallRequest) async -> Bool {
            busy = request.catalogName ?? request.identifier
            defer { busy = nil }
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.installAgentPlugin(request)
                guard result.ok != false else {
                    notice = ToolsNotice.error(result.error ?? ToolsMessages.failedAction)
                    return false
                }
                notice = installNotice(result)
                await load()
                return true
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
                return false
            }
        }

        /// Loads an enabled plugin for the active profile now, so open chats get its tools without a restart.
        func activate(_ name: String) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let active = try await rest.activeProfile().active
                let scope = await rest.profile ?? active
                guard let home = try await rest.profiles().first(where: { $0.name == scope })?.path else {
                    notice = ToolsNotice.error("The server did not report the folder of this profile.")
                    return
                }
                _ = try await rest.activateAgentPlugin(name, home: home)
                notice = ToolsNotice.info("\(name) is loaded for open chats.")
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        private func installNotice(_ result: AgentPluginResult) -> ToolsNotice? {
            if let missing = result.missingEnv, !missing.isEmpty {
                return ToolsNotice.info("Set \(missing.joined(separator: ", ")) on the server. The plugin needs it.")
            }
            if result.restartRequired == true {
                return ToolsNotice.info("Restart the gateway to load the plugin.")
            }
            return nil
        }
    }

    /// The agent plugins: installed ones with their switch and actions, then the catalog with installs and updates.
    struct AgentPluginsScreen: View {
        @State private var model: AgentPluginsModel
        @State private var showsGitInstall = false
        private let connections: ConnectionsModel?

        /// `connections` is nil when the shell has none. The screen then says that no server is connected.
        init(connections: ConnectionsModel?) {
            self.connections = connections
            _model = State(initialValue: AgentPluginsModel(connections: connections))
        }

        var body: some View {
            List {
                if let error = model.loadError {
                    Section { ToolsNoticeRow(notice: ToolsNotice.error(error)) }
                }
                if let notice = model.notice {
                    Section { ToolsNoticeRow(notice: notice) }
                }
                Section {
                    ForEach(model.plugins) { plugin in
                        pluginRow(plugin)
                    }
                } header: {
                    Text("Installed")
                } footer: {
                    Text("Changes apply after the gateway restarts, unless the row says otherwise.")
                }
                Section {
                    ForEach(model.catalog) { entry in
                        catalogRow(entry)
                    }
                } header: {
                    Text("Catalog")
                } footer: {
                    Text("Entries are pinned to a reviewed commit. Updates move the pin.")
                }
                if !model.withdrawn.isEmpty {
                    Section("Withdrawn") {
                        ForEach(Array(model.withdrawn.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Plugin")
                                    .font(HermesFont.body)
                                if let reason = item.reason {
                                    Text(reason)
                                        .font(HermesFont.footnote)
                                        .foregroundStyle(HermesColor.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agent plugins")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Install from git", systemImage: "arrow.down.circle") {
                            showsGitInstall = true
                        }
                        Button("Rescan folders", systemImage: "arrow.clockwise") {
                            Task { await model.rescan() }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("plugins.more")
                }
            }
            .sheet(isPresented: $showsGitInstall) {
                NavigationStack {
                    AgentPluginInstallSheet(model: model)
                }
            }
            .confirmationDialog(
                "Update \(model.pendingUpdate?.name ?? "plugin")?",
                isPresented: pendingUpdateBinding,
                titleVisibility: .visible
            ) {
                Button("Accept and update") {
                    guard let pending = model.pendingUpdate else { return }
                    model.pendingUpdate = nil
                    Task { await model.update(pending.name, accept: true) }
                }
            } message: {
                Text((model.pendingUpdate?.lines ?? []).joined(separator: "\n"))
            }
            .onAppear { Task { await model.load() } }
            .refreshable { await model.load() }
        }

        private var pendingUpdateBinding: Binding<Bool> {
            Binding(
                get: { model.pendingUpdate != nil },
                set: { showing in
                    if !showing {
                        model.pendingUpdate = nil
                    }
                })
        }

        private func pluginRow(_ plugin: AgentPlugin) -> some View {
            Toggle(
                isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { value in Task { await model.setEnabled(plugin, enabled: value) } })
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(HermesFont.body.weight(.semibold))
                        if let version = plugin.version {
                            Text(version)
                                .font(HermesFont.codeSmall)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    if let description = plugin.description, !description.isEmpty {
                        Text(description)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(2)
                    }
                    Text(sourceLabel(plugin.source))
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                    if plugin.authRequired == true {
                        Text("Needs sign-in: \(plugin.authCommand ?? "run its sign-in command on the server").")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.statusWarning)
                    }
                    if let removed = plugin.removedReason {
                        Text("Withdrawn: \(removed)")
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.statusWarning)
                    }
                }
            }
            .disabled(model.busy == plugin.name)
            .swipeActions(edge: .leading) {
                if plugin.canUpdateGit == true {
                    Button("Update") {
                        Task { await model.update(plugin.name) }
                    }
                    .tint(HermesColor.accent)
                }
            }
            .swipeActions(edge: .trailing) {
                if plugin.canRemove == true {
                    Button("Remove", role: .destructive) {
                        Task { await model.remove(plugin.name) }
                    }
                }
            }
            .contextMenu {
                Button("Load for open chats") {
                    Task { await model.activate(plugin.name) }
                }
                .disabled(!plugin.isEnabled)
            }
            .accessibilityIdentifier("plugins.row.\(plugin.name)")
        }

        private func catalogRow(_ entry: AgentPluginCatalogEntry) -> some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title ?? entry.name)
                        .font(HermesFont.body.weight(.semibold))
                    if let description = entry.description, !description.isEmpty {
                        Text(description)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(3)
                    }
                    Text([entry.version, entry.tier].compactMap { $0 }.joined(separator: " · "))
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Spacer(minLength: 8)
                catalogAction(entry)
            }
            .accessibilityIdentifier("plugins.catalog.\(entry.name)")
        }

        @ViewBuilder
        private func catalogAction(_ entry: AgentPluginCatalogEntry) -> some View {
            if entry.updateAvailable == true {
                Button("Update") {
                    Task { await model.update(entry.name) }
                }
                .buttonStyle(.bordered)
                .disabled(model.busy != nil)
            } else if entry.installed != true {
                Button("Install") {
                    Task {
                        _ = await model.install(
                            AgentPluginInstallRequest(catalogName: entry.name, force: false, enable: true))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.busy != nil)
                .accessibilityIdentifier("plugins.install.\(entry.name)")
            }
        }

        private func sourceLabel(_ source: String?) -> String {
            switch source ?? "" {
            case "bundled":
                return "Bundled with Hermes"
            case "user":
                return "Your plugins folder"
            case "git":
                return "Installed from git"
            case "project":
                return "Project folder"
            default:
                return source ?? "Unknown source"
            }
        }
    }

    /// Installs a plugin from a git repository, optionally pinned to a full commit id. A short id is refused.
    struct AgentPluginInstallSheet: View {
        let model: AgentPluginsModel
        @State private var url = ""
        @State private var pin = ""
        @State private var enable = true
        @Environment(\.dismiss) private var dismiss

        init(model: AgentPluginsModel) {
            self.model = model
        }

        var body: some View {
            Form {
                Section {
                    TextField("https://github.com/owner/repo.git", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("plugins.install.url")
                } header: {
                    Text("Git URL")
                } footer: {
                    Text("Add #folder to install one plugin from a repository with several.")
                }
                Section {
                    TextField("Full commit id (optional)", text: $pin)
                        .font(HermesFont.code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("plugins.install.pin")
                } header: {
                    Text("Pin to a commit")
                } footer: {
                    Text(
                        pinIsValid
                            ? "Leave it empty to install the default branch."
                            : "Use all 40 characters of the commit id.")
                }
                Section {
                    Toggle("Enable after install", isOn: $enable)
                }
            }
            .navigationTitle("Install plugin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install") {
                        Task {
                            let request = AgentPluginInstallRequest(
                                identifier: trimmedURL, ref: pin.isEmpty ? nil : pin, enable: enable)
                            if await model.install(request) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canInstall)
                    .accessibilityIdentifier("plugins.install.confirm")
                }
            }
        }

        private var trimmedURL: String {
            url.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var pinIsValid: Bool {
            pin.isEmpty || AgentPluginInstallRequest.isCommitSHA(pin)
        }

        private var canInstall: Bool {
            !trimmedURL.isEmpty && pinIsValid && model.busy == nil
        }
    }

    #Preview("Agent plugins, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { AgentPluginsScreen(connections: .preview()) }
    }

    #Preview("Agent plugins, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { AgentPluginsScreen(connections: .preview()) }
    }

    #Preview("Agent plugins, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { AgentPluginsScreen(connections: .preview()) }
    }

    #Preview("Agent plugins, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { AgentPluginsScreen(connections: .preview()) }
    }
#endif
