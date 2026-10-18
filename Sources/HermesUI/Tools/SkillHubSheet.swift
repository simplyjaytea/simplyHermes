#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import SwiftUI

    /// The skill hub (WP-51): the official catalog, a search across the hub sources, and the preview, scan and install
    /// of one skill. Nothing is installed until the user taps Install.
    @MainActor
    @Observable
    final class SkillHubModel {
        /// The optional-skills catalog. Rows the profile has are marked.
        private(set) var official: [HubSkill] = []
        /// Results of the last search, one per identifier.
        private(set) var results: [HubSkill] = []
        /// Sources that did not answer the last search in time.
        private(set) var timedOut: [String] = []
        /// Installed hub skills of the profile, by identifier.
        private(set) var installed: [String: SkillHubInstall] = [:]
        /// The SKILL.md and file list of the skill on screen.
        private(set) var preview: SkillHubPreview?
        /// The install-time scan of the skill on screen.
        private(set) var scan: SkillHubScan?
        private(set) var isLoading = false
        private(set) var isSearching = false
        var notice: ToolsNotice?
        let actions = ToolsActionRunner()
        @ObservationIgnored private let connections: ConnectionsModel?

        init(connections: ConnectionsModel?) {
            self.connections = connections
        }

        /// True when the profile has the skill, from the catalog or from the installed list.
        func isInstalled(_ skill: HubSkill) -> Bool {
            skill.installed == true || installed[skill.id] != nil
        }

        /// Reads the catalog and what is installed.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                official = try await rest.officialSkillCatalog().skills
                installed = try await rest.skillHubSources().installed ?? [:]
                notice = nil
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Searches every hub source. The server can take a while, so the sheet shows progress. An empty query clears
        /// the results.
        func search(_ query: String) async {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                results = []
                timedOut = []
                return
            }
            isSearching = true
            defer { isSearching = false }
            do {
                let rest = try await ToolsServer.rest(connections)
                let found = try await rest.searchSkillHub(text)
                results = found.results
                timedOut = found.timedOut ?? []
                installed.merge(found.installed ?? [:]) { _, new in new }
                notice = nil
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Reads the SKILL.md, the files and the scan of a hub skill. Nothing is installed.
        func inspect(_ identifier: String) async {
            preview = nil
            scan = nil
            do {
                let rest = try await ToolsServer.rest(connections)
                preview = try await rest.previewSkillHub(identifier)
                scan = try await rest.scanSkillHub(identifier)
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }

        /// Installs a hub skill and waits for the server. Returns true when the skill is installed.
        func install(_ identifier: String, title: String) async -> Bool {
            do {
                let rest = try await ToolsServer.rest(connections)
                let start = try await rest.installHubSkill(identifier)
                let status = try await actions.run(start, title: "Installing \(title)", rest: rest)
                guard status.succeeded else {
                    notice = ToolsNotice.error(ToolsMessages.failedAction)
                    return false
                }
                notice = nil
                installed = try await rest.skillHubSources().installed ?? [:]
                return true
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
                return false
            }
        }

        /// Starts the update of every installed hub skill and waits for the server.
        func updateInstalled() async {
            do {
                let rest = try await ToolsServer.rest(connections)
                let start = try await rest.updateHubSkills()
                let status = try await actions.run(start, title: "Updating hub skills", rest: rest)
                notice = status.succeeded ? nil : ToolsNotice.error(ToolsMessages.failedAction)
                installed = try await rest.skillHubSources().installed ?? [:]
            } catch {
                notice = ToolsNotice.error(ToolsMessages.text(for: error))
            }
        }
    }

    /// Browses the hub from the Skills screen. The catalog shows first. A search covers every hub source.
    struct SkillHubSheet: View {
        @State private var model: SkillHubModel
        @State private var query = ""
        @State private var confirmsUpdate = false
        @Environment(\.dismiss) private var dismiss

        init(connections: ConnectionsModel?) {
            _model = State(initialValue: SkillHubModel(connections: connections))
        }

        var body: some View {
            List {
                if let activity = model.actions.activity {
                    Section { ToolsActivityRow(activity: activity) }
                }
                if let notice = model.notice {
                    Section { ToolsNoticeRow(notice: notice) }
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    officialSection
                } else {
                    resultsSection
                }
            }
            .navigationTitle("Skill hub")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search skill hubs")
            .onSubmit(of: .search) {
                Task { await model.search(query) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("skillHub.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        confirmsUpdate = true
                    } label: {
                        Label("Update installed", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.actions.activity != nil)
                    .accessibilityIdentifier("skillHub.update")
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .confirmationDialog(
                "Update installed hub skills?", isPresented: $confirmsUpdate, titleVisibility: .visible
            ) {
                Button("Update") {
                    Task { await model.updateInstalled() }
                }
            } message: {
                Text("The server updates every hub skill installed for this profile. The app has no way to undo an update.")
            }
        }

        private var officialSection: some View {
            Section {
                ForEach(model.official) { skill in
                    hubRow(skill)
                }
            } header: {
                Text("Official catalog")
            } footer: {
                Text("Search to look in every hub source.")
            }
        }

        private var resultsSection: some View {
            Section {
                if model.isSearching {
                    ProgressView()
                }
                ForEach(model.results) { skill in
                    hubRow(skill)
                }
            } header: {
                Text("Results")
            } footer: {
                if !model.timedOut.isEmpty {
                    Text("No answer in time from \(model.timedOut.joined(separator: ", ")).")
                }
            }
        }

        private func hubRow(_ skill: HubSkill) -> some View {
            NavigationLink {
                SkillHubDetailScreen(model: model, skill: skill)
            } label: {
                HubSkillRow(skill: skill, isInstalled: model.isInstalled(skill))
            }
            .accessibilityIdentifier("skillHub.row.\(skill.id)")
        }
    }

    /// One hub skill in a list: its name, its source, and whether the profile has it.
    private struct HubSkillRow: View {
        let skill: HubSkill
        let isInstalled: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(skill.name)
                        .font(HermesFont.body.weight(.semibold))
                    Spacer(minLength: 8)
                    if isInstalled {
                        Text("Installed")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.statusConnected)
                    }
                }
                if let description = skill.description, !description.isEmpty {
                    Text(description)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
                if let source = skill.source {
                    Text(source)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
        }
    }

    /// One hub skill: what it says, its files, the scan, and Install. Install asks first and names the source and trust level.
    struct SkillHubDetailScreen: View {
        let model: SkillHubModel
        let skill: HubSkill
        @State private var confirmsInstall = false

        init(model: SkillHubModel, skill: HubSkill) {
            self.model = model
            self.skill = skill
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
                    LabeledContent("Source", value: skill.source ?? "Unknown")
                    LabeledContent("Trust", value: skill.trustLevel ?? "Unknown")
                    if let repo = skill.repo {
                        LabeledContent("Repository", value: repo)
                    }
                } footer: {
                    Text(skill.description ?? "")
                }
                if let scan = model.scan {
                    scanSection(scan)
                }
                installSection
                if let preview = model.preview {
                    Section("Files") {
                        ForEach(preview.files ?? [], id: \.self) { file in
                            Text(file)
                                .font(HermesFont.code)
                        }
                    }
                    if let markdown = preview.skillMd {
                        Section("SKILL.md") {
                            Text(markdown)
                                .font(HermesFont.code)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.inspect(skill.id) }
            .confirmationDialog(
                "Install \(skill.name)?", isPresented: $confirmsInstall, titleVisibility: .visible
            ) {
                if model.scan?.policy == "ask" {
                    Button("Install anyway", role: .destructive) {
                        Task { _ = await model.install(skill.id, title: skill.name) }
                    }
                } else {
                    Button("Install") {
                        Task { _ = await model.install(skill.id, title: skill.name) }
                    }
                }
            } message: {
                Text(installMessage)
            }
        }

        /// What the install does: where the skill comes from, its trust level, the scan verdict and what it adds.
        private var installMessage: String {
            var lines = ["From \(skill.source ?? "an unknown source"), trust \(skill.trustLevel ?? "unknown")."]
            lines.append("Scan verdict: \(model.scan?.verdict ?? "unknown").")
            if model.scan?.policy == "ask" {
                lines.append("The scan asks for a review first.")
            }
            lines.append("It adds the skill and its files to this profile.")
            return lines.joined(separator: "\n")
        }

        private func scanSection(_ scan: SkillHubScan) -> some View {
            Section {
                LabeledContent("Verdict", value: scan.verdict ?? "Unknown")
                LabeledContent("Policy", value: policyLabel(scan.policy))
                if let reason = scan.policyReason, !reason.isEmpty {
                    Text(reason)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                ForEach(Array((scan.findings ?? []).enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.description ?? finding.category ?? "Finding")
                            .font(HermesFont.subheadline)
                        Text([finding.severity, finding.file].compactMap { $0 }.joined(separator: " · "))
                            .font(HermesFont.codeSmall)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
            } header: {
                Text("Scan")
            }
        }

        private var installSection: some View {
            Section {
                if model.isInstalled(skill) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(HermesColor.statusConnected)
                } else {
                    Button {
                        confirmsInstall = true
                    } label: {
                        Text(model.scan?.policy == "block" ? "Blocked by the scan" : "Install")
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(model.scan == nil || model.scan?.policy == "block" || model.actions.activity != nil)
                    .accessibilityIdentifier("skillHub.install")
                }
            } footer: {
                if model.scan?.policy == "block", let reason = model.scan?.policyReason {
                    Text(reason)
                }
            }
        }

        private func policyLabel(_ policy: String?) -> String {
            switch policy ?? "" {
            case "allow":
                return "Installs directly"
            case "ask":
                return "Asks before install"
            case "block":
                return "Blocked"
            default:
                return "Unknown"
            }
        }
    }

    #Preview("Skill hub, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { SkillHubSheet(connections: .preview()) }
    }

    #Preview("Skill hub, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { SkillHubSheet(connections: .preview()) }
    }

    #Preview("Skill hub, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { SkillHubSheet(connections: .preview()) }
    }

    #Preview("Skill hub, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { SkillHubSheet(connections: .preview()) }
    }
#endif
