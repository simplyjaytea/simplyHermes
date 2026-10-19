#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// What the editor saves. `create` makes a job in `profile`: a bot's profile, or the default profile for System.
    /// `edit` changes a job in `profile`, the profile that owns it. Its schedule is sent only when it is a 5-field cron
    /// expression that changed, and `enabledChange` is set only when the enabled switch moved, so the model pauses or
    /// resumes the job.
    public enum CronJobSave: Sendable, Equatable {
        case create(CronJobCreate, profile: String)
        case edit(id: String, profile: String, changes: CronJobUpdate, enabledChange: Bool?)
    }

    /// Creates or edits a cron job (plan Q36): name, prompt, bot, a schedule from presets with a time wheel, and raw
    /// cron under Advanced with the next runs in the profile's time zone. A job whose schedule is not a 5-field cron
    /// keeps that schedule. `onSave` makes the change. When it throws, the editor says why and stays open.
    public struct CronJobEditor: View {
        private let job: CronJob?
        private let bots: [String]
        private let onSave: @MainActor (CronJobSave) async throws -> Void
        private let serverTimeZone: @MainActor (String) async -> String?

        @Environment(\.dismiss) private var dismiss
        @State private var name: String
        @State private var prompt: String
        @State private var bot: String?
        @State private var preset: CronPreset
        @State private var time: Date
        @State private var weekday: Int
        @State private var dayOfMonth: Int
        /// The raw cron text. It is the schedule only while `isCustom` is set; presets write it otherwise.
        @State private var rawSchedule: String
        @State private var isCustom: Bool
        @State private var enabled: Bool
        @State private var showsAdvanced: Bool
        /// The profile's time zone as an IANA name, "" for the server's own time. Nil until read, or when it fails.
        @State private var zoneName: String?
        @State private var isSaving = false
        @State private var saveError: String?

        /// `job` nil creates a job in `presetBot` (nil is System). For an existing job the bot is its profile, and
        /// `presetBot` is ignored. `serverTimeZone` reads a profile's time zone for the preview of the next runs.
        public init(
            job: CronJob?, bots: [String], presetBot: String?,
            onSave: @escaping @MainActor (CronJobSave) async throws -> Void,
            serverTimeZone: @escaping @MainActor (String) async -> String? = { _ in nil }
        ) {
            self.job = job
            self.bots = bots
            self.onSave = onSave
            self.serverTimeZone = serverTimeZone
            let (settings, custom) = Self.initialSchedule(for: job)
            _name = State(initialValue: job?.name ?? "")
            _prompt = State(initialValue: job?.prompt ?? job?.promptPreview ?? "")
            _bot = State(initialValue: job == nil ? presetBot : job?.botName)
            _preset = State(initialValue: settings.preset)
            _time = State(initialValue: Self.clock(hour: settings.hour, minute: settings.minute))
            _weekday = State(initialValue: settings.weekday)
            _dayOfMonth = State(initialValue: settings.dayOfMonth)
            _rawSchedule = State(initialValue: job?.schedule?.cronExpression ?? settings.expression)
            _isCustom = State(initialValue: custom)
            _enabled = State(initialValue: job?.isEnabled ?? true)
            _showsAdvanced = State(initialValue: custom)
        }

        public var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $name)
                            .accessibilityIdentifier("automation.name")
                    } header: {
                        Text("Name")
                    } footer: {
                        if trimmed(name).isEmpty { Text("Give the automation a name.") }
                    }
                    Section {
                        TextField("What should Hermes do?", text: $prompt, axis: .vertical)
                            .lineLimit(3...8)
                            .accessibilityIdentifier("automation.prompt")
                    } header: {
                        Text("Prompt")
                    } footer: {
                        if trimmed(prompt).isEmpty { Text("Write what Hermes should do when it runs.") }
                    }
                    botSection
                    scheduleSection
                    Section {
                        Toggle("Enabled", isOn: $enabled)
                            .accessibilityIdentifier("automation.enabled")
                    } footer: {
                        Text(enabled ? "Runs on its schedule." : "Paused. It runs only when you run it now.")
                    }
                    if let saveError {
                        Section {
                            Label(saveError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(HermesColor.destructive)
                                .accessibilityIdentifier("automation.error")
                        }
                    }
                }
                .disabled(isSaving)
                .navigationTitle(job == nil ? "New automation" : "Edit automation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(job == nil ? "Create" : "Save") { save() }
                            .disabled(!canSave)
                            .accessibilityIdentifier("automation.save")
                    }
                }
                .task(id: profile) { zoneName = await serverTimeZone(profile) }
            }
        }

        // MARK: Bot

        private var botSection: some View {
            Section {
                if job == nil {
                    Picker("Bot", selection: $bot) {
                        Text("System").tag(String?.none)
                        ForEach(botChoices, id: \.self) { botName in
                            Text(botName).tag(Optional(botName))
                        }
                    }
                    .accessibilityIdentifier("automation.bot")
                } else {
                    LabeledContent("Bot", value: bot ?? "System")
                }
            } footer: {
                Text(
                    job == nil
                        ? "A bot's automations run in its profile. System runs in the default profile."
                        : "An automation stays with its bot.")
            }
        }

        // MARK: Schedule

        private var scheduleSection: some View {
            Section {
                if isEditableSchedule {
                    Picker("Repeat", selection: presetBinding) {
                        ForEach(CronPreset.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("automation.schedule.preset")
                    if preset != .hourly {
                        DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .accessibilityIdentifier("automation.schedule.time")
                    }
                    if preset == .weekly {
                        Picker("Day", selection: weekdayBinding) {
                            ForEach(0..<7, id: \.self) { day in
                                Text(Calendar.current.weekdaySymbols[day]).tag(day)
                            }
                        }
                    }
                    if preset == .monthly {
                        Stepper("Day \(dayOfMonth) of the month", value: dayBinding, in: 1...28)
                    }
                    DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                        advancedFields
                    }
                } else {
                    LabeledContent("Repeats", value: job?.schedule?.summary ?? "No schedule")
                        .accessibilityIdentifier("automation.schedule.fixed")
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text(scheduleFooter)
            }
        }

        @ViewBuilder
        private var advancedFields: some View {
            TextField("minute hour day month weekday", text: rawBinding)
                .font(HermesFont.code)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("automation.schedule.raw")
            if let scheduleError {
                Text(scheduleError)
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.destructive)
            }
            if !nextRuns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nextRunsTitle)
                        .font(HermesFont.footnote.weight(.semibold))
                    ForEach(nextRuns, id: \.self) { run in
                        Text(run.formatted(date: .abbreviated, time: .shortened))
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
            }
        }

        /// New automations and 5-field cron jobs are scheduled here. Any other schedule stays as the server has it.
        private var isEditableSchedule: Bool {
            job == nil || job?.schedule?.cronExpression != nil
        }

        private var scheduleFooter: String {
            if isEditableSchedule { return CronExpression.describe(expression) }
            return "Not a 5-field cron expression, so the schedule stays as it is when you save."
        }

        /// The expression the job is saved with: the raw text when it is custom, else the preset's.
        private var expression: String {
            isCustom
                ? rawSchedule : preset.expression(hour: hour, minute: minute, weekday: weekday, dayOfMonth: dayOfMonth)
        }

        private var hour: Int { Calendar.current.component(.hour, from: time) }

        private var minute: Int { Calendar.current.component(.minute, from: time) }

        /// Why the expression cannot be saved. Only a schedule the editor changes is checked.
        private var scheduleError: String? {
            isEditableSchedule ? CronExpression.validate(expression)?.message : nil
        }

        /// The next three runs, counted in the profile's time zone while the server names one.
        private var nextRuns: [Date] {
            guard isEditableSchedule, scheduleError == nil, let parsed = try? CronExpression.parse(expression) else {
                return []
            }
            return parsed.nextRuns(after: .now, count: 3, calendar: previewCalendar)
        }

        /// The zone the preview counts in. Nil when the server did not name one.
        private var previewZone: TimeZone? {
            guard let zoneName, !zoneName.isEmpty else { return nil }
            return TimeZone(identifier: zoneName)
        }

        private var previewCalendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = previewZone ?? .current
            return calendar
        }

        private var nextRunsTitle: String {
            if let previewZone { return "Next runs in \(previewZone.identifier)" }
            return "Next runs (approximate)"
        }

        /// The preset controls take over from custom text.
        private var presetBinding: Binding<CronPreset> {
            Binding(
                get: { preset },
                set: { value in
                    preset = value
                    isCustom = false
                })
        }

        private var timeBinding: Binding<Date> {
            Binding(
                get: { time },
                set: { value in
                    time = value
                    isCustom = false
                })
        }

        private var weekdayBinding: Binding<Int> {
            Binding(
                get: { weekday },
                set: { value in
                    weekday = value
                    isCustom = false
                })
        }

        private var dayBinding: Binding<Int> {
            Binding(
                get: { dayOfMonth },
                set: { value in
                    dayOfMonth = value
                    isCustom = false
                })
        }

        /// Typed raw cron. Text that a preset writes goes back to that preset; any other text stays custom until it
        /// matches one.
        private var rawBinding: Binding<String> {
            Binding(
                get: { expression },
                set: { text in
                    rawSchedule = text
                    isCustom = true
                    guard let settings = CronPreset.matching(text) else { return }
                    preset = settings.preset
                    time = Self.clock(hour: settings.hour, minute: settings.minute)
                    weekday = settings.weekday
                    dayOfMonth = settings.dayOfMonth
                    isCustom = false
                })
        }

        // MARK: Saving

        /// The profile the job is created in, or that owns it. The default profile is System.
        private var profile: String {
            job?.profile ?? bot ?? "default"
        }

        private var botChoices: [String] {
            var choices = bots
            if let bot, !choices.contains(bot) { choices.append(bot) }
            return choices
        }

        private var canSave: Bool {
            !isSaving && !trimmed(name).isEmpty && !trimmed(prompt).isEmpty && scheduleError == nil
        }

        private func save() {
            let change: CronJobSave
            if let job {
                change = .edit(
                    id: job.id, profile: profile, changes: editChanges(for: job),
                    enabledChange: enabled == job.isEnabled ? nil : enabled)
            } else {
                change = .create(
                    CronJobCreate(schedule: expression, name: trimmed(name), prompt: trimmed(prompt), paused: !enabled),
                    profile: profile)
            }
            isSaving = true
            saveError = nil
            Task {
                do {
                    try await onSave(change)
                    dismiss()
                } catch {
                    saveError = AutomationsModel.failureText(
                        error, fallback: "Could not save. Check the connection and try again.")
                }
                isSaving = false
            }
        }

        /// What an edit sends: the name and prompt, and the schedule only when it is a cron expression that changed.
        private func editChanges(for job: CronJob) -> CronJobUpdate {
            let scheduleChanged = isEditableSchedule && expression != job.schedule?.cronExpression
            return CronJobUpdate(
                name: trimmed(name), prompt: trimmed(prompt), schedule: scheduleChanged ? expression : nil)
        }

        private func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // MARK: Helpers

        /// The preset to show for a job. A schedule no preset writes opens as custom text, and a schedule that is not
        /// a 5-field cron opens as custom text too, so it is never rewritten.
        private static func initialSchedule(for job: CronJob?) -> (CronPresetSettings, Bool) {
            let fallback = CronPresetSettings(preset: .daily)
            guard let job else { return (fallback, false) }
            guard let expression = job.schedule?.cronExpression else { return (fallback, true) }
            if let matched = CronPreset.matching(expression) { return (matched, false) }
            return (fallback, true)
        }

        private static func clock(hour: Int, minute: Int) -> Date {
            Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        }
    }

    #Preview("New, outer", traits: .fixedLayout(width: 466, height: 678)) {
        CronJobEditor(job: nil, bots: ["ana", "bo"], presetBot: "ana") { _ in }
    }

    #Preview("Edit, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        CronJobEditor(job: AutomationSamples.jobs[0], bots: ["ana", "bo"], presetBot: nil) { _ in }
    }

    #Preview("Edit custom, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        CronJobEditor(
            job: CronJob(
                jobId: "c1", name: "Quarter hours", schedule: CronSchedule(kind: "cron", expr: "*/15 9-17 * * 1-5"),
                profile: "ana", isDefaultProfile: false),
            bots: ["ana", "bo"], presetBot: nil
        ) { _ in }
    }

    #Preview("New, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        CronJobEditor(job: nil, bots: ["ana", "bo"], presetBot: nil) { _ in }
    }
#endif
