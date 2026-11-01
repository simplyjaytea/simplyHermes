#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Full configuration screen for a bot: identity, model, soul, skills, toolsets, MCP, and export (PR B).
    public struct BotSettingsScreen: View {
        @State private var model: BotSettingsModel
        @Environment(\.dismiss) private var dismiss

        public init(entry: BotRosterEntry, connections: ConnectionsModel) {
            _model = State(
                initialValue: BotSettingsModel(entry: entry, connections: connections))
        }

        init(entry: BotRosterEntry, connections: ConnectionsModel, rosterModel: BotsModel?) {
            _model = State(
                initialValue: BotSettingsModel(entry: entry, connections: connections, rosterModel: rosterModel))
        }

        public var body: some View {
            NavigationStack {
                Group {
                    if model.isLoading {
                        ProgressView("Loading bot settings…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let draft = model.draft {
                        form(for: draft)
                    } else {
                        VStack(spacing: 12) {
                            Text("Could not load bot settings.")
                                .font(HermesFont.headline)
                            if let error = model.errorMessage {
                                Text(error)
                                    .font(HermesFont.footnote)
                                    .foregroundStyle(HermesColor.destructive)
                            }
                            Button("Try Again") {
                                Task { await model.load() }
                            }
                            .buttonStyle(HermesButtonStyle(.secondary))
                        }
                        .padding(20)
                    }
                }
                .navigationTitle(model.entry.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                if await model.save() { dismiss() }
                            }
                        }
                        .disabled(cannotSave)
                        .accessibilityIdentifier("botSettings.save")
                    }
                }
                .task {
                    if model.draft == nil {
                        await model.load()
                    }
                }
                .confirmationDialog(
                    "Confirm Model Change",
                    isPresented: $model.confirmRequired,
                    titleVisibility: .visible
                ) {
                    Button("Confirm and Save", role: .destructive) {
                        Task {
                            if await model.confirmExpensiveModelChange() {
                                dismiss()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        model.confirmRequired = false
                    }
                } message: {
                    Text(model.confirmMessage ?? "This model may incur higher usage costs.")
                }
                .sheet(item: $model.shareFile) { file in
                    ActivitySheet(items: [file.url])
                }
            }
        }

        private var cannotSave: Bool {
            guard let draft = model.draft else { return true }
            return model.isSaving || !draft.isDirty || !draft.isValid
        }

        @ViewBuilder
        private func form(for draft: BotSettingsDraft) -> some View {
            Form {
                statusAndErrorSections()
                identitySection(for: draft)
                modelSection(for: draft)
                soulSection(for: draft)
                skillsSection(for: draft)
                toolsetsSection(for: draft)
                mcpSection(for: draft)
                exportSection()
            }
            .disabled(model.isSaving)
        }

        @ViewBuilder
        private func statusAndErrorSections() -> some View {
            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.destructive)
                        .accessibilityIdentifier("botSettings.error")
                }
            }

            if let status = model.statusMessage, model.errorMessage == nil {
                Section {
                    Text(status)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.accent)
                }
            }
        }

        @ViewBuilder
        private func identitySection(for draft: BotSettingsDraft) -> some View {
            Section("Identity") {
                TextField("Name", text: binding(for: \.title))
                    .accessibilityIdentifier("botSettings.title")
                TextField("Role (optional)", text: binding(for: \.role), axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("botSettings.role")
                AvatarPicker(
                    avatar: binding(for: \.avatar),
                    name: draft.title.isEmpty ? model.entry.profile : draft.title,
                    tint: model.entry.tint
                )
                Toggle("Pinned", isOn: binding(for: \.isPinned))
                Toggle("Hidden", isOn: binding(for: \.isHidden))
            } footer: {
                if let problem = draft.problems.first(where: {
                    if case .titleTooLong = $0 { return true }
                    if case .roleTooLong = $0 { return true }
                    return false
                }) {
                    Text(problem.userMessage)
                        .foregroundStyle(HermesColor.destructive)
                } else {
                    Text("Handle @\(model.entry.profile). Hidden bots move to the bottom of the roster.")
                }
            }
        }

        @ViewBuilder
        private func modelSection(for draft: BotSettingsDraft) -> some View {
            Section("Model & Provider") {
                if !model.modelOptions.isEmpty {
                    Picker(
                        "Provider",
                        selection: Binding(
                            get: { draft.provider },
                            set: { newProvider in
                                model.draft?.provider = newProvider
                                let providerOpt = model.modelOptions.first(where: { $0.slug == newProvider })
                                let availableModels = providerOpt?.models ?? []
                                if !availableModels.isEmpty && !availableModels.contains(draft.model) {
                                    model.draft?.model = availableModels.first ?? ""
                                }
                            }
                        )
                    ) {
                        ForEach(model.modelOptions, id: \.slug) { opt in
                            Text(opt.name).tag(opt.slug)
                        }
                    }
                    let currentProvider = model.modelOptions.first(where: { $0.slug == draft.provider })
                    let availableModels = currentProvider?.models ?? []
                    if !availableModels.isEmpty {
                        Picker("Model", selection: binding(for: \.model)) {
                            ForEach(availableModels, id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                        }
                    } else {
                        TextField("Model", text: binding(for: \.model))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } else {
                    TextField("Provider", text: binding(for: \.provider))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model", text: binding(for: \.model))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } footer: {
                if draft.problems.contains(.modelIncomplete) {
                    Text(BotSettingsProblem.modelIncomplete.userMessage)
                        .foregroundStyle(HermesColor.destructive)
                } else {
                    Text("Configures the default provider and model used by this bot.")
                }
            }
        }

        @ViewBuilder
        private func soulSection(for draft: BotSettingsDraft) -> some View {
            Section("Personality (SOUL)") {
                TextField("SOUL instructions", text: binding(for: \.soul), axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityIdentifier("botSettings.soul")
            } footer: {
                HStack {
                    if let soulProblem = draft.problems.first(where: {
                        if case .soulTooLong = $0 { return true }
                        return false
                    }) {
                        Text(soulProblem.userMessage)
                            .foregroundStyle(HermesColor.destructive)
                    } else {
                        Text("Personality and core instructions for this bot.")
                    }
                    Spacer()
                    Text("\(draft.soul.count) / \(BotSettingsDraft.maxSoulLength)")
                        .font(HermesFont.caption.monospacedDigit())
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
        }

        @ViewBuilder
        private func skillsSection(for draft: BotSettingsDraft) -> some View {
            Section {
                TextField("Search skills", text: $model.skillSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                let matching = draft.filteredSkills(matching: model.skillSearchText)
                if matching.isEmpty {
                    Text("No matching skills")
                        .foregroundStyle(HermesColor.secondaryText)
                } else {
                    ForEach(matching) { skill in
                        Toggle(skill.name, isOn: skillBinding(for: skill.name))
                    }
                }
            } header: {
                Text("Skills (\(draft.enabledSkillsCount) of \(draft.totalSkillsCount) enabled)")
            } footer: {
                Text("Skills extend what this bot can perform. Disabled skills are excluded from execution.")
            }
        }

        @ViewBuilder
        private func toolsetsSection(for draft: BotSettingsDraft) -> some View {
            Section {
                if !draft.toolsetsPinned {
                    HStack {
                        Text("Inherited from settings")
                            .foregroundStyle(HermesColor.secondaryText)
                        Spacer()
                        Button("Customize") {
                            model.draft?.customizeToolsets()
                        }
                        .buttonStyle(HermesButtonStyle(.tinted))
                    }
                } else {
                    HStack {
                        Text("Customized for this bot")
                            .foregroundStyle(HermesColor.accent)
                    }
                    ForEach(draft.toolsets) { toolset in
                        Toggle(isOn: toolsetBinding(for: toolset.name)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(toolset.label ?? toolset.name)
                                    .font(HermesFont.body)
                                if let desc = toolset.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(HermesFont.caption)
                                        .foregroundStyle(HermesColor.secondaryText)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Toolsets")
            } footer: {
                Text(
                    draft.toolsetsPinned
                        ? "Toolsets are customized for this bot. Resetting toolset inheritance to global settings is desktop-only."
                        : "Toolsets are currently inherited from global settings. Tap Customize to choose specific toolsets."
                )
            }
        }

        @ViewBuilder
        private func mcpSection(for draft: BotSettingsDraft) -> some View {
            if !draft.mcpServers.isEmpty {
                Section("MCP Servers") {
                    ForEach(draft.mcpServers) { server in
                        Toggle(isOn: mcpBinding(for: server.name)) {
                            HStack {
                                Text(server.name)
                                if let transport = server.transport {
                                    Spacer()
                                    Text(transport)
                                        .font(HermesFont.caption)
                                        .foregroundStyle(HermesColor.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func exportSection() -> some View {
            Section {
                Button {
                    Task { await model.exportBot() }
                } label: {
                    HStack {
                        Label("Export this bot", systemImage: "square.and.arrow.up")
                        Spacer()
                        if model.isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isExporting)
            } footer: {
                Text("Export creates an archive of this bot's configuration and memory to save or share.")
            }
        }

        private func binding<T>(for keyPath: WritableKeyPath<BotSettingsDraft, T>) -> Binding<T> {
            Binding(
                get: {
                    guard let draft = model.draft else { fatalError("Draft requested while nil") }
                    return draft[keyPath: keyPath]
                },
                set: { model.draft?[keyPath: keyPath] = $0 }
            )
        }

        private func skillBinding(for name: String) -> Binding<Bool> {
            Binding(
                get: {
                    model.draft?.skills.first { $0.name == name }?.enabled ?? true
                },
                set: { _ in
                    model.draft?.toggleSkill(named: name)
                }
            )
        }

        private func toolsetBinding(for name: String) -> Binding<Bool> {
            Binding(
                get: {
                    model.draft?.toolsets.first { $0.name == name }?.enabled ?? true
                },
                set: { _ in
                    model.draft?.toggleToolset(named: name)
                }
            )
        }

        private func mcpBinding(for name: String) -> Binding<Bool> {
            Binding(
                get: {
                    model.draft?.mcpServers.first { $0.name == name }?.enabled ?? true
                },
                set: { _ in
                    model.draft?.toggleMcpServer(named: name)
                }
            )
        }
    }
#endif
