#if canImport(UIKit)
    import HermesKit

    /// Sample automations for previews. The app does not show them.
    public enum AutomationSamples {
        public static let jobs: [CronJob] = [
            CronJob(
                jobId: "9c1f0a2e5b7d", name: "Morning summary",
                prompt: "Summarise yesterday's chats and list open approvals.",
                promptPreview: "Summarise yesterday's chats and list open approvals.",
                schedule: CronSchedule(kind: "cron", expr: "0 9 * * 1-5", display: "0 9 * * 1-5"), deliver: "local",
                nextRunAt: "2026-10-19T09:00:00+00:00", lastRunAt: "2026-10-16T09:00:00+00:00", lastStatus: "ok",
                enabled: true, profile: "ana", isDefaultProfile: false),
            CronJob(
                jobId: "4b8e6d1a0c93", name: "Nightly backup check", promptPreview: "Check the backup log.",
                schedule: CronSchedule(kind: "cron", expr: "30 2 * * *", display: "30 2 * * *"), deliver: "local",
                nextRunAt: "2026-10-19T02:30:00+00:00", lastStatus: "error", lastError: "backup.log not found",
                enabled: true, profile: "default", isDefaultProfile: true),
            CronJob(
                jobId: "e27a9c4f1b06", name: "Weekly digest", promptPreview: "Write the weekly digest.",
                schedule: CronSchedule(kind: "cron", expr: "0 17 * * 5", display: "0 17 * * 5"),
                enabled: false, pausedReason: "Paused by user", profile: "bo", isDefaultProfile: false),
            CronJob(
                jobId: "2d7b5e9f3a10", name: "Status ping", promptPreview: "Check the gateway status.",
                schedule: CronSchedule(kind: "interval", minutes: 30, display: "every 30m"),
                nextRunAt: "2026-10-18T12:30:00+00:00", enabled: true, profile: "ana", isDefaultProfile: false),
        ]
    }
#endif
