import Foundation

/// One cron job, from `GET /api/cron/jobs?profile=all` or `GET /api/cron/jobs/{job_id}`. The server sends the job
/// record of `cron/jobs.py`; the list also annotates each row with the profile that owns it. The record's key is `id`
/// (`job_id` is read too). Only the fields the app reads are modelled, and unknown keys are ignored. Every field but
/// the id is optional, so a sparse row still decodes.
public struct CronJob: Sendable, Equatable, Decodable, Identifiable {
    /// Server id.
    public var jobId: String
    /// Name as stored. When it is empty, ``displayName`` shows the start of the prompt.
    public var name: String?
    /// The full prompt.
    public var prompt: String?
    /// The start of the prompt, for a server that sends only that.
    public var promptPreview: String?
    /// When the job runs, as the server stores it. Only a 5-field cron schedule is edited in the app.
    public var schedule: CronSchedule?
    /// Where results go, such as `local`.
    public var deliver: String?
    /// When the next run is due, as the server wrote it (ISO 8601).
    public var nextRunAt: String?
    /// When the last run started, as the server wrote it.
    public var lastRunAt: String?
    /// Outcome of the last run, as the server words it.
    public var lastStatus: String?
    /// Error of the last run.
    public var lastError: String?
    /// Error sending the result of the last run.
    public var lastDeliveryError: String?
    /// False when the job is paused. Nil counts as enabled.
    public var enabled: Bool?
    /// Why the job is paused, when it is.
    public var pausedReason: String?
    /// The profile that owns the job. A named profile is a bot; the default profile is System (see ``botName``).
    public var profile: String?
    /// True when the owning profile is the default profile.
    public var isDefaultProfile: Bool?

    /// Creates a job. The server fills the real values; this is for previews and tests.
    public init(
        jobId: String, name: String? = nil, prompt: String? = nil, promptPreview: String? = nil,
        schedule: CronSchedule? = nil, deliver: String? = nil, nextRunAt: String? = nil, lastRunAt: String? = nil,
        lastStatus: String? = nil, lastError: String? = nil, lastDeliveryError: String? = nil,
        enabled: Bool? = nil, pausedReason: String? = nil, profile: String? = nil, isDefaultProfile: Bool? = nil
    ) {
        self.jobId = jobId
        self.name = name
        self.prompt = prompt
        self.promptPreview = promptPreview
        self.schedule = schedule
        self.deliver = deliver
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.lastDeliveryError = lastDeliveryError
        self.enabled = enabled
        self.pausedReason = pausedReason
        self.profile = profile
        self.isDefaultProfile = isDefaultProfile
    }

    private enum Keys: String, CodingKey {
        case jobId, id, name, prompt, promptPreview, schedule, deliver, nextRunAt, lastRunAt, lastStatus, lastError
        case lastDeliveryError, enabled, pausedReason, profile, isDefaultProfile
    }

    /// Reads the record under the keys the REST client's snake_case decoding produces. A row with neither `job_id`
    /// nor `id` throws, so the list drops it.
    public init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        let snakeJobID = try? keyed.decodeIfPresent(String.self, forKey: .jobId)
        guard let identifier = snakeJobID ?? (try? keyed.decode(String.self, forKey: .id)) else {
            throw DecodingError.keyNotFound(
                Keys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A cron job has no id"))
        }
        jobId = identifier
        name = try? keyed.decodeIfPresent(String.self, forKey: .name)
        prompt = try? keyed.decodeIfPresent(String.self, forKey: .prompt)
        promptPreview = try? keyed.decodeIfPresent(String.self, forKey: .promptPreview)
        schedule = try? keyed.decodeIfPresent(CronSchedule.self, forKey: .schedule)
        deliver = try? keyed.decodeIfPresent(String.self, forKey: .deliver)
        nextRunAt = try? keyed.decodeIfPresent(String.self, forKey: .nextRunAt)
        lastRunAt = try? keyed.decodeIfPresent(String.self, forKey: .lastRunAt)
        lastStatus = try? keyed.decodeIfPresent(String.self, forKey: .lastStatus)
        lastError = try? keyed.decodeIfPresent(String.self, forKey: .lastError)
        lastDeliveryError = try? keyed.decodeIfPresent(String.self, forKey: .lastDeliveryError)
        enabled = try? keyed.decodeIfPresent(Bool.self, forKey: .enabled)
        pausedReason = try? keyed.decodeIfPresent(String.self, forKey: .pausedReason)
        profile = try? keyed.decodeIfPresent(String.self, forKey: .profile)
        isDefaultProfile = try? keyed.decodeIfPresent(Bool.self, forKey: .isDefaultProfile)
    }

    /// The job's id, for lists.
    public var id: String { jobId }

    /// The bot that owns the job: its named profile. Nil is System: the default profile, or a job with no profile.
    public var botName: String? {
        if isDefaultProfile == true { return nil }
        let text = profile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty || text == "default" ? nil : text
    }

    /// The name to show: the stored name, else the first line of the prompt.
    public var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        let firstLine = (promptPreview ?? prompt ?? "").components(separatedBy: .newlines).first ?? ""
        let text = firstLine.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Untitled automation" : text
    }

    /// Whether the job runs on its schedule. A missing flag counts as enabled.
    public var isEnabled: Bool { enabled ?? true }

    /// The next run as a date, when the server's time can be read.
    public var nextRun: Date? { CronTimestamp.date(from: nextRunAt) }

    /// The last run as a date, when the server's time can be read.
    public var lastRun: Date? { CronTimestamp.date(from: lastRunAt) }
}

/// One past run, from `GET /api/cron/jobs/{job_id}/runs`, which answers `{"runs": [...], "limit": N}`. A row is an
/// agent session or a script-only output document. The server words the outcome in ``title``, for example
/// `FAILED · provider timeout`.
public struct CronRun: Sendable, Equatable, Decodable {
    /// The session or output id, when the server sends one.
    public var id: String?
    /// The outcome and what ran, as the server words it.
    public var title: String?
    /// The start of what the run produced.
    public var preview: String?
    /// When the run started. The server sends seconds since 1970; an ISO 8601 string is read too.
    public var started: Date?
    /// When the run ended, when it has.
    public var ended: Date?
    /// True while the run is still going.
    public var isActive: Bool?

    /// Creates a run. The server fills the real values; this is for previews and tests.
    public init(
        id: String? = nil, title: String? = nil, preview: String? = nil, started: Date? = nil, ended: Date? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.started = started
        self.ended = ended
        self.isActive = isActive
    }

    private enum Keys: String, CodingKey {
        case id, title, preview, startedAt, endedAt, isActive
    }

    /// Reads a run row. The times are read whether the server sent seconds or a string.
    public init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        id = try? keyed.decodeIfPresent(String.self, forKey: .id)
        title = try? keyed.decodeIfPresent(String.self, forKey: .title)
        preview = try? keyed.decodeIfPresent(String.self, forKey: .preview)
        started = Self.date(try? keyed.decodeIfPresent(JSONValue.self, forKey: .startedAt))
        ended = Self.date(try? keyed.decodeIfPresent(JSONValue.self, forKey: .endedAt))
        isActive = try? keyed.decodeIfPresent(Bool.self, forKey: .isActive)
    }

    /// Reads seconds since 1970, or an ISO 8601 string.
    private static func date(_ value: JSONValue?) -> Date? {
        switch value {
        case .double(let seconds)?: Date(timeIntervalSince1970: seconds)
        case .int(let seconds)?: Date(timeIntervalSince1970: TimeInterval(seconds))
        case .string(let text)?: CronTimestamp.date(from: text)
        default: nil
        }
    }
}

/// A place results can be delivered, from `GET /api/cron/delivery-targets`, which answers `{"targets": [...]}` with
/// rows of `id` and `name`. ``value`` is what the job's `deliver` field takes. A bare string or an object with
/// `value`, `id`, `target` or `deliver` is also read.
public struct CronDeliveryTarget: Sendable, Equatable, Decodable, Identifiable {
    /// What the `deliver` field takes, such as `local`.
    public var value: String
    /// Name to show, when the server sends one.
    public var label: String?

    /// The target's value, for lists.
    public var id: String { value }

    /// Creates a target.
    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label
    }

    private enum Keys: String, CodingKey {
        case value, id, target, deliver, label, name, title
    }

    /// Reads a bare string, or an object with one of the value keys and an optional label.
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            value = text
            label = nil
            return
        }
        let keyed = try decoder.container(keyedBy: Keys.self)
        guard let key = [Keys.value, .id, .target, .deliver].first(where: { keyed.contains($0) }) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No delivery target value"))
        }
        value = try keyed.decode(String.self, forKey: key)
        label = [Keys.label, .name, .title].compactMap { try? keyed.decodeIfPresent(String.self, forKey: $0) }.first
    }
}

/// Body of `POST /api/cron/jobs`. `schedule` is required and must be a 5-field cron expression. Nil fields are left
/// out, so the server's defaults apply (a missing `deliver` is `local`).
public struct CronJobCreate: Sendable, Equatable, Codable {
    /// Name of the job.
    public var name: String?
    /// What the agent does when the job runs.
    public var prompt: String?
    /// A 5-field cron expression.
    public var schedule: String
    /// True to create the job paused.
    public var paused: Bool?
    /// Where results go, such as `local`.
    public var deliver: String?

    /// Creates a body. `schedule` comes first, so the optional fields after it can take defaults.
    public init(
        schedule: String, name: String? = nil, prompt: String? = nil, paused: Bool? = nil, deliver: String? = nil
    ) {
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.paused = paused
        self.deliver = deliver
    }
}

/// Body of `PUT /api/cron/jobs/{job_id}`. `updates` holds the fields to change, by their server names. Fields that are
/// left out stay as they are.
public struct CronJobUpdate: Sendable, Equatable, Codable {
    /// Changed fields, keyed by server name.
    public var updates: [String: JSONValue]

    /// Creates a body from the fields to change.
    public init(updates: [String: JSONValue]) {
        self.updates = updates
    }

    /// Changes the name, prompt and schedule. Nil values are left out.
    public init(name: String? = nil, prompt: String? = nil, schedule: String? = nil) {
        var updates: [String: JSONValue] = [:]
        if let name { updates["name"] = .string(name) }
        if let prompt { updates["prompt"] = .string(prompt) }
        if let schedule { updates["schedule"] = .string(schedule) }
        self.updates = updates
    }
}

/// Reads the times the cron API sends. ISO 8601 with a zone is read as written, with or without fractional seconds.
/// A time with no zone is read in the device's time zone.
public enum CronTimestamp {
    /// The date `text` names, or nil when it is missing or not a time this reads.
    public static func date(from text: String?) -> Date? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return local.date(from: trimmed)
    }
}
