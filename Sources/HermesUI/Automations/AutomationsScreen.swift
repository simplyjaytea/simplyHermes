#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Automations tab (plan Q37): one list of cron jobs with the chips All, Bots and System. Bots are grouped by
    /// their profile, and System is the default profile. Opening a row shows its detail (WP-50).
    public struct AutomationsScreen: View {
        private let connections: ConnectionsModel
        @State private var model: AutomationsModel
        @State private var isCreating = false

        public init(connections: ConnectionsModel) {
            self.connections = connections
            _model = State(initialValue: AutomationsModel(connections: connections))
        }

        /// Previews pass a model with fixed jobs, so the list shows without a server.
        init(connections: ConnectionsModel, model: AutomationsModel) {
            self.connections = connections
            _model = State(initialValue: model)
        }

        public var body: some View {
            Group {
                if connections.active == nil && !model.hasLoaded {
                    ContentUnavailableView(
                        "No server connected", systemImage: "server.rack",
                        description: Text("Add a server in Settings to see its automations."))
                } else {
                    AutomationsListView(model: model, onCreate: { isCreating = true })
                }
            }
            .navigationTitle("Automations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("New automation", systemImage: "plus")
                    }
                    .accessibilityIdentifier("automations.new")
                }
            }
            .task(id: connections.active?.id) { await model.attach() }
            .onDisappear { model.detach() }
            .sheet(isPresented: $isCreating) {
                CronJobEditor(
                    job: nil, bots: model.botNames, presetBot: presetBot,
                    onSave: { change in try await model.save(change) },
                    serverTimeZone: { profile in await model.timeZoneName(forProfile: profile) })
            }
        }

        /// A new automation made while the Bots filter shows one bot belongs to that bot.
        private var presetBot: String? {
            if case .bot(let name) = model.filter { return name }
            return nil
        }
    }

    /// The list: the filter chips on top, one section per bot and one for System, and the states for loading, errors
    /// and empty lists.
    public struct AutomationsListView: View {
        private let model: AutomationsModel
        private let onCreate: () -> Void
        @State private var pendingDelete: CronJob?

        /// `onCreate` opens the editor from the empty state. The toolbar button belongs to ``AutomationsScreen``.
        public init(model: AutomationsModel, onCreate: @escaping () -> Void = {}) {
            self.model = model
            self.onCreate = onCreate
        }

        public var body: some View {
            List {
                if let loadError = model.loadError {
                    Section {
                        Label(loadError, systemImage: "wifi.slash")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityIdentifier("automations.error")
                    }
                }
                if let actionError = model.actionError {
                    Section {
                        Label(actionError, systemImage: "exclamationmark.triangle")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.destructive)
                            .accessibilityIdentifier("automations.actionError")
                    }
                }
                if model.isLoading && !model.hasLoaded {
                    skeleton
                } else {
                    ForEach(model.sections) { section in
                        Section(section.title) {
                            ForEach(section.jobs) { job in row(job) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .refreshable { await model.refresh() }
            .overlay { emptyState }
            .confirmationDialog(
                "Delete this automation?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible, presenting: pendingDelete
            ) { job in
                Button("Delete", role: .destructive) { Task { await model.delete(job) } }
            } message: { job in
                Text("\"\(job.displayName)\" is deleted from the server. This cannot be undone.")
            }
            .navigationDestination(for: AutomationRoute.self) { route in
                CronJobDetailView(model: model, jobID: route.id)
            }
        }

        private var filterBar: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CronJobFilter.chips, id: \.self) { chip in
                        HermesChip(chip.title, isSelected: model.filter == chip) { model.filter = chip }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .background(.bar)
            .accessibilityIdentifier("automations.filters")
        }

        private func row(_ job: CronJob) -> some View {
            NavigationLink(value: AutomationRoute(id: job.id)) {
                AutomationRow(job: job)
            }
            .swipeActions(edge: .leading) {
                Button(job.isEnabled ? "Pause" : "Resume", systemImage: job.isEnabled ? "pause" : "play") {
                    Task { await model.setEnabled(job, !job.isEnabled) }
                }
                .tint(HermesColor.statusWarning)
                Button("Run now", systemImage: "play.fill") {
                    Task { await model.runNow(job) }
                }
                .tint(HermesColor.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = job }
            }
        }

        /// Placeholder rows while the first list loads, in place of a spinner (plan Q46).
        private var skeleton: some View {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Automation name")
                        .font(HermesFont.body.weight(.semibold))
                    Text("Every day at 09:00")
                        .font(HermesFont.footnote)
                    Text("Next run tomorrow")
                        .font(HermesFont.footnote)
                }
                .redacted(reason: .placeholder)
                .hermesShimmer()
                .accessibilityHidden(true)
            }
        }

        @ViewBuilder
        private var emptyState: some View {
            if model.jobs.isEmpty, let loadError = model.loadError, !model.isLoading {
                ContentUnavailableView(
                    "Automations unavailable", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if model.hasLoaded, model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("No automations yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Create one for a bot or for the system. It runs on its schedule.")
                } actions: {
                    Button("New automation", action: onCreate)
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                }
            } else if model.hasLoaded, model.sections.isEmpty {
                ContentUnavailableView(
                    filterEmptyTitle, systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Choose another filter to see the rest."))
            }
        }

        private var filterEmptyTitle: String {
            switch model.filter {
            case .all: "No automations yet"
            case .bots: "No bot automations"
            case .system: "No System automations"
            case .bot(let name): "Nothing for \(name)"
            }
        }
    }

    /// Opens one automation's detail from the list.
    private struct AutomationRoute: Hashable {
        let id: String
    }

    /// One automation in the list: its name, its schedule in words, and either its pause, its last failure or its next
    /// run.
    struct AutomationRow: View {
        let job: CronJob

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(job.displayName)
                        .font(HermesFont.body.weight(.semibold))
                        .lineLimit(1)
                    if !job.isEnabled {
                        Image(systemName: "pause.circle.fill")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityLabel("Paused")
                    }
                }
                Text(job.schedule?.summary ?? "No schedule")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .lineLimit(1)
                Text(statusLine)
                    .font(HermesFont.footnote)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("automation.row.\(job.id)")
        }

        private var failed: Bool {
            job.lastError != nil || job.lastStatus == "error"
        }

        private var statusLine: String {
            if !job.isEnabled { return "Paused" }
            if failed { return "Last run failed" }
            if let next = job.nextRun {
                return "Next " + next.formatted(date: .abbreviated, time: .shortened)
            }
            return "No upcoming run"
        }

        private var statusColor: Color {
            job.isEnabled && failed ? HermesColor.destructive : HermesColor.secondaryText
        }
    }

    /// A model with fixed jobs and a filter, for previews. It makes no calls.
    @MainActor
    private func sampleModel(
        filter: CronJobFilter = .all, jobs: [CronJob] = AutomationSamples.jobs
    ) -> AutomationsModel {
        let model = AutomationsModel.preview(jobs)
        model.filter = filter
        return model
    }

    #Preview("Loaded, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            AutomationsScreen(connections: .preview(), model: sampleModel())
        }
    }

    #Preview("Bots filter, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            AutomationsScreen(connections: .preview(), model: sampleModel(filter: .bots))
        }
    }

    #Preview("Empty, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            AutomationsScreen(connections: .preview(), model: sampleModel(jobs: []))
        }
    }

    #Preview("No server, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            AutomationsScreen(connections: .preview([]), model: AutomationsModel(connections: .preview([])))
        }
    }
#endif
