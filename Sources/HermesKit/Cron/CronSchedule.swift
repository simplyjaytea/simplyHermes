import Foundation

/// When a job runs, as the server stores it: `{"kind": "cron" | "interval" | "once", "expr", "minutes", "run_at",
/// "display"}` (`cron/jobs.py`). A bare string is read as the schedule's own text. Read tolerantly: a field of the
/// wrong type is dropped, so one odd field does not hide the job.
public struct CronSchedule: Sendable, Equatable, Decodable {
    /// `cron`, `interval` or `once`. Nil when the server sent a bare string or no kind.
    public var kind: String?
    /// The expression of a `cron` schedule.
    public var expr: String?
    /// The period of an `interval` schedule, in minutes.
    public var minutes: Double?
    /// When a `once` schedule runs, as the server wrote it.
    public var runAt: String?
    /// The server's own words for the schedule, such as `every 30m`.
    public var display: String?

    /// Creates a schedule. The server fills the real values; this is for previews and tests.
    public init(
        kind: String? = nil, expr: String? = nil, minutes: Double? = nil, runAt: String? = nil, display: String? = nil
    ) {
        self.kind = kind
        self.expr = expr
        self.minutes = minutes
        self.runAt = runAt
        self.display = display
    }

    private enum Keys: String, CodingKey {
        case kind, expr, minutes, runAt, display
    }

    /// Reads the server's object, or a bare string as the expression.
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(expr: text, display: text)
            return
        }
        let keyed = try decoder.container(keyedBy: Keys.self)
        self.init(
            kind: try? keyed.decodeIfPresent(String.self, forKey: .kind),
            expr: try? keyed.decodeIfPresent(String.self, forKey: .expr),
            minutes: try? keyed.decodeIfPresent(Double.self, forKey: .minutes),
            runAt: try? keyed.decodeIfPresent(String.self, forKey: .runAt),
            display: try? keyed.decodeIfPresent(String.self, forKey: .display))
    }

    /// The 5-field cron expression a job's schedule is edited with, or nil for any other schedule.
    public var cronExpression: String? {
        guard kind == nil || kind == "cron", let expr, CronExpression.validate(expr) == nil else { return nil }
        return expr
    }

    /// The schedule in words, for lists and details.
    public var summary: String {
        if let expr, kind == nil || kind == "cron" { return CronExpression.describe(expr) }
        if let display, !display.isEmpty { return display }
        if let minutes { return "Every \(Int(minutes)) minutes" }
        if let runAt, !runAt.isEmpty { return "Once at \(runAt)" }
        return "No schedule"
    }
}
