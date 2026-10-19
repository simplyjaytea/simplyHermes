#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// One automation: its status, schedule, prompt, last run and past runs, and the actions Run now, Pause or Resume,
    /// Edit and Delete (WP-50). It shows the job as the list has it. Nothing changes on the server until the user acts.
    public struct CronJobDetailView: View {
        private let model: AutomationsModel
        private let jobID: String

        @Environment(\.dismiss) private var dismiss
        @State private var runs: [CronRun] = []
        @State private var runsFailed = false
        @State private var editing: CronJob?
        @State private var confirmsDelete = false
        @State private var notice: String?

        public init(model: AutomationsModel, jobID: String) {
            self.model = model
            self.jobID = jobID
        }

        /// The job as the list has it now. Nil when it was deleted elsewhere.
        private var job: CronJob? {
            model.jobs.first { $0.id == jobID }
        }

        public var body: some View {
            Group {
                if let job {
                    details(job)
                } else {
                    ContentUnavailableView(
                        "Automation not found", systemImage: "questionmark.circle",
                        description: Text("It may have been deleted on the server."))
                }
            }
            .navigationTitle(job?.displayName ?? "Automation")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await model.refresh()
                await loadRuns()
            }
            .task(id: model.jobs) { await loadRuns() }
            .sheet(item: $editing) { job in
                CronJobEditor(
                    job: job, bots: model.botNames, presetBot: nil,
                    onSave: { change in try await model.save(change) },
                    serverTimeZone: { profile in await model.timeZoneName(forProfile: profile) })
            }
            .onChange(of: editing) { _, newValue in
                if newValue == nil { Task { await loadRuns() } }
            }
            .confirmationDialog("Delete this automation?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                if let job {
                    Button("Delete", role: .destructive) { Task { await delete(job) } }
                }
            } message: {
                Text("It is deleted from the server and its schedule stops. This cannot be undone.")
            }
        }

        private func details(_ job: CronJob) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notice {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.destructive)
                            .accessibilityIdentifier("automation.notice")
                    }
                    if let actionError = model.actionError {
                        Label(actionError, systemImage: "exclamationmark.triangle")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.destructive)
                            .accessibilityIdentifier("automation.actionError")
                    }
                    statusCard(job)
                    scheduleCard(job)
                    promptCard(job)
                    lastRunCard(job)
                    runsCard
                    actions(job)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(HermesColor.groupedBackground)
        }

        private func statusCard(_ job: CronJob) -> some View {
            HermesCard {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.isEnabled ? "Active" : "Paused")
                        .font(HermesFont.headline)
                    Spacer(minLength: 8)
                    Text(job.botName.map { "Bot: \($0)" } ?? "System")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if !job.isEnabled, let reason = job.pausedReason {
                    Text(reason)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if job.isEnabled, let next = job.nextRun {
                    Text("Next run " + next.formatted(date: .abbreviated, time: .shortened))
                        .font(HermesFont.footnote)
                }
            }
        }

        private func scheduleCard(_ job: CronJob) -> some View {
            HermesCard {
                sectionLabel("Repeats")
                Text(job.schedule?.summary ?? "No schedule")
                    .font(HermesFont.body)
                if let expression = job.schedule?.expr {
                    Text(expression)
                        .font(HermesFont.code)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if let deliver = job.deliver {
                    Text("Results: \(deliver)")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
        }

        private func promptCard(_ job: CronJob) -> some View {
            HermesCard {
                sectionLabel("Prompt")
                Text(job.prompt ?? job.promptPreview ?? "No prompt")
                    .font(HermesFont.body)
                    .textSelection(.enabled)
            }
        }

        private func lastRunCard(_ job: CronJob) -> some View {
            HermesCard {
                sectionLabel("Last run")
                if let last = job.lastRun {
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                        .font(HermesFont.body)
                } else {
                    Text("Has not run yet")
                        .font(HermesFont.body)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if let status = job.lastStatus {
                    Text("Status: \(status)")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if let error = job.lastError {
                    Text(error)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.destructive)
                }
                if let delivery = job.lastDeliveryError {
                    Text("Delivery failed: \(delivery)")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.destructive)
                }
            }
        }

        private var runsCard: some View {
            HermesCard {
                sectionLabel("Past runs")
                if runsFailed {
                    Text("Could not load the past runs. Pull down to try again.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                } else if runs.isEmpty {
                    Text("No runs yet.")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                } else {
                    ForEach(runs.indices, id: \.self) { index in
                        runRow(runs[index])
                    }
                }
            }
        }

        private func runRow(_ run: CronRun) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title ?? "Run")
                    .font(HermesFont.footnote.weight(.semibold))
                if let started = run.started {
                    Text(started.formatted(date: .abbreviated, time: .shortened))
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                if let preview = run.preview {
                    Text(preview)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func actions(_ job: CronJob) -> some View {
            VStack(spacing: 10) {
                Button("Run now") {
                    Task {
                        if await model.runNow(job) { await loadRuns() }
                    }
                }
                .buttonStyle(HermesButtonStyle(.primary))
                .accessibilityIdentifier("automation.runNow")
                Button(job.isEnabled ? "Pause" : "Resume") {
                    Task { await model.setEnabled(job, !job.isEnabled) }
                }
                .buttonStyle(HermesButtonStyle(.secondary))
                .accessibilityIdentifier("automation.pause")
                Button("Edit") { Task { await openEditor(job) } }
                    .buttonStyle(HermesButtonStyle(.tinted))
                    .accessibilityIdentifier("automation.edit")
                Button("Delete", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(HermesButtonStyle(.destructive))
                    .accessibilityIdentifier("automation.delete")
            }
        }

        private func sectionLabel(_ title: String) -> some View {
            Text(title)
                .font(HermesFont.footnote.weight(.semibold))
                .foregroundStyle(HermesColor.secondaryText)
        }

        /// Reads the job's own record first, so the editor knows the profile that owns it.
        private func openEditor(_ job: CronJob) async {
            notice = nil
            do {
                editing = try await model.job(id: job.id)
            } catch {
                notice = AutomationsModel.failureText(error, fallback: "Could not open this automation. Try again.")
            }
        }

        private func delete(_ job: CronJob) async {
            if await model.delete(job) {
                dismiss()
            }
        }

        /// Reads the past runs. A failed read says so and keeps the last list.
        private func loadRuns() async {
            do {
                runs = try await model.runs(of: jobID)
                runsFailed = false
            } catch is CancellationError {
                return
            } catch {
                runsFailed = true
            }
        }
    }

    #Preview("System, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            CronJobDetailView(model: .preview(AutomationSamples.jobs), jobID: AutomationSamples.jobs[1].id)
        }
    }

    #Preview("Bot, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            CronJobDetailView(model: .preview(AutomationSamples.jobs), jobID: AutomationSamples.jobs[0].id)
        }
    }

    #Preview("Paused, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            CronJobDetailView(model: .preview(AutomationSamples.jobs), jobID: AutomationSamples.jobs[2].id)
        }
    }

    #Preview("Interval, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            CronJobDetailView(model: .preview(AutomationSamples.jobs), jobID: AutomationSamples.jobs[3].id)
        }
    }
#endif
