#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import SwiftUI

    /// The skills of the active profile (WP-51). Reads the list, turns skills on and off, reads and saves SKILL.md, and
    /// removes hub installs. Every call goes through ``ToolsServer``, so it is scoped to the active profile.
    @MainActor
    @Observable
    final class SkillsModel {
        private(set) var skills: [SkillInfo] = []
        private(set) var isLoading = false
        /// Why the list could not load. Nil when it loaded.
        private(set) var loadError: String?
        /// The result of the last change, or why it did not happen.
        var notice: ToolsNotice?
        let actions = ToolsActionRunner()
        @ObservationIgnored private let connections: ConnectionsModel?

        init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        /// Reads the installed skills, sorted by category and then by name.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                skills = try await rest.skills().sorted {
                    ($0.category ?? "", $0.name) < ($1.category ?? "", $1.name)
                }
                loadError = nil
            } catch {
                loadError = ToolsMessages.text(for: error)
            }
        }

        /// The skill as the list has it now, so a detail screen shows the latest state.
        func skill(named name: String) -> SkillInfo? {
            skills.first { $0.name == name }
        }

        /// Turns a skill on or off for the active profile.
        func setEnabled(_ name: String, enabled: Bool) async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let result = try await rest.setSkillEnabled(name, enabled: enabled)
                guard result.ok != false else {
                    notice = ToolsNotice.error("The server did not save the change.")
                    return
                }
                if let index = skills.firstIndex(where: { $0.name == name }) {
                    skills[index].enabled = enabled
                }
                notice = nil
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Removes a hub install and waits for the server to finish. Returns true when the skill is gone.
        func uninstall(_ name: String) async -> Bool {
            do {
                let rest = try await ToolsServer.rest(connections)
                let start = try await rest.uninstallHubSkill(name)
                let status = try await actions.run(start, title: "Removing \(name)", rest: rest)
                guard status.succeeded else {
                    notice = ToolsNotice.error(ToolsMessages.failedAction)
                    return false
                }
                notice = nil
                await load()
                return true
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
                return false
            }
        }

        /// The SKILL.md text of an installed skill.
        func content(of name: String) async throws -> String {
            let rest = try await ToolsServer.rest(connections)
            return try await rest.skillContent(name).content
        }

        /// Replaces the SKILL.md text. The server checks the frontmatter and refuses a bad file, which throws.
        func save(_ name: String, content: String) async throws {
            let rest = try await ToolsServer.rest(connections)
            _ = try await rest.updateSkillContent(name, content: content)
        }
    }

    /// The installed skills, with the skill hub behind the plus button (WP-51).
    struct SkillsScreen: View {
        @State private var model: SkillsModel
        @State private var query = ""
        @State private var showsHub = false
        private let connections: ConnectionsModel?

        /// `connections` is nil when the shell has none. The list then says that no server is connected.
        init(connections: ConnectionsModel?) {
            self.connections = connections
            _model = State(initialValue: SkillsModel(connections: connections))
        }

        var body: some View {
            List {
                if let activity = model.actions.activity {
                    Section { ToolsActivityRow(activity: activity) }
                }
                if let error = model.loadError {
                    Section { ToolsNoticeRow(notice: ToolsNotice.error(error)) }
                }
                if let notice = model.notice {
                    Section { ToolsNoticeRow(notice: notice) }
                }
                Section {
                    ForEach(visibleSkills) { skill in
                        NavigationLink {
                            SkillDetailScreen(model: model, name: skill.name)
                        } label: {
                            SkillRow(skill: skill)
                        }
                        .accessibilityIdentifier("skills.row.\(skill.name)")
                    }
                } footer: {
                    Text("Skills the server loads into chats. Turn one off to keep it out.")
                }
            }
            .navigationTitle("Skills")
            .searchable(text: $query, prompt: "Search skills")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsHub = true
                    } label: {
                        Label("Skill hub", systemImage: "plus")
                    }
                    .accessibilityIdentifier("skills.hub")
                }
            }
            .sheet(isPresented: $showsHub, onDismiss: { Task { await model.load() } }) {
                NavigationStack {
                    SkillHubSheet(connections: connections)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
        }

        /// The skills that match the search text, by name or description.
        private var visibleSkills: [SkillInfo] {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return model.skills }
            return model.skills.filter {
                $0.name.localizedCaseInsensitiveContains(text)
                    || ($0.description ?? "").localizedCaseInsensitiveContains(text)
            }
        }
    }

    /// One skill in the list: its name, what it does, and whether it is on.
    private struct SkillRow: View {
        let skill: SkillInfo

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(skill.name)
                        .font(HermesFont.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(skill.enabled ? "On" : "Off")
                        .font(HermesFont.footnote)
                        .foregroundStyle(skill.enabled ? HermesColor.statusConnected : HermesColor.secondaryText)
                }
                if let description = skill.description, !description.isEmpty {
                    Text(description)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    /// One skill: whether it is on, its details, its SKILL.md (editable), and removing a hub install.
    struct SkillDetailScreen: View {
        let model: SkillsModel
        let name: String
        @State private var text: String?
        @State private var loadError: String?
        @State private var isEditing = false
        @State private var draft = ""
        @State private var saveError: String?
        @State private var isSaving = false
        @State private var confirmsRemoval = false
        @Environment(\.dismiss) private var dismiss

        init(model: SkillsModel, name: String) {
            self.model = model
            self.name = name
        }

        var body: some View {
            if let skill = model.skill(named: name) {
                details(skill)
            } else {
                ContentUnavailableView("Skill not found", systemImage: "questionmark.folder")
                    .navigationTitle(name)
            }
        }

        private func details(_ skill: SkillInfo) -> some View {
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
                            get: { skill.enabled },
                            set: { value in Task { await model.setEnabled(skill.name, enabled: value) } })
                    )
                    .accessibilityIdentifier("skill.enabled")
                } footer: {
                    Text(skill.description ?? "No description.")
                }
                Section {
                    LabeledContent("Category", value: skill.category ?? "None")
                    LabeledContent("From", value: sourceLabel(skill.provenance))
                    if let usage = skill.usage {
                        LabeledContent("Uses", value: "\(usage)")
                    }
                }
                Section {
                    skillText
                } header: {
                    Text("SKILL.md")
                } footer: {
                    if isEditing {
                        Text("The server checks the frontmatter when you save.")
                    }
                }
                if SkillProvenance(label: skill.provenance).isHubInstall {
                    Section {
                        Button("Remove skill", role: .destructive) {
                            confirmsRemoval = true
                        }
                        .disabled(model.actions.activity != nil)
                        .accessibilityIdentifier("skill.remove")
                    }
                }
            }
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editToolbar }
            .task { await loadText() }
            .confirmationDialog(
                "Remove \(skill.name)?", isPresented: $confirmsRemoval, titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        if await model.uninstall(skill.name) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("The server deletes the skill's files. Chats that used it keep their history.")
            }
        }

        @ViewBuilder
        private var skillText: some View {
            if isEditing {
                TextEditor(text: $draft)
                    .font(HermesFont.code)
                    .frame(minHeight: 260)
                    .accessibilityIdentifier("skill.editor")
                if let saveError {
                    ToolsNoticeRow(notice: ToolsNotice.error(saveError))
                }
            } else if let text {
                Text(text)
                    .font(HermesFont.code)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("skill.content")
            } else if let loadError {
                ToolsNoticeRow(notice: ToolsNotice.error(loadError))
            } else {
                ProgressView()
            }
        }

        @ToolbarContentBuilder
        private var editToolbar: some ToolbarContent {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditing = false
                        saveError = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || draft == text)
                    .accessibilityIdentifier("skill.save")
                }
            } else if text != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        draft = text ?? ""
                        isEditing = true
                    }
                    .accessibilityIdentifier("skill.edit")
                }
            }
        }

        private func loadText() async {
            guard text == nil else { return }
            do {
                text = try await model.content(of: name)
                loadError = nil
            } catch {
                loadError = ToolsMessages.text(for: error)
            }
        }

        private func save() async {
            isSaving = true
            defer { isSaving = false }
            do {
                try await model.save(name, content: draft)
                text = draft
                isEditing = false
                saveError = nil
            } catch {
                saveError = ToolsMessages.text(for: error)
            }
        }

        private func sourceLabel(_ provenance: String?) -> String {
            switch SkillProvenance(label: provenance) {
            case .hub:
                return "Skill hub"
            case .bundled:
                return "Shipped with Hermes"
            case .external:
                return "External folder"
            case .agent:
                return "Written on the server"
            case .other:
                return provenance ?? "Unknown"
            }
        }
    }

    #Preview("Skills, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SkillsScreen(connections: .preview()) }
    }

    #Preview("Skills, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SkillsScreen(connections: .preview()) }
    }

    #Preview("Skills, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SkillsScreen(connections: .preview()) }
    }

    #Preview("Skills, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SkillsScreen(connections: .preview()) }
    }
#endif
