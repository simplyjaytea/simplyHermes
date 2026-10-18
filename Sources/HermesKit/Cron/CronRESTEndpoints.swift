import Foundation

// The `/api/cron/*` answers are not described by the OpenAPI document (their response schemas are empty), so the
// list, single-job, run and target answers are read either as a bare value or inside an object under the key the
// server's own tools use. Write answers are not read: callers reload the list after a change.

/// Keys an answer may wrap its value in.
private enum CronEnvelopeKey: String, CodingKey {
    case job
    case jobs
    case runs
    case targets
}

/// Decodes one element on its own, so a row that does not decode is dropped instead of failing the whole answer.
private struct CronLossy<Item: Decodable & Sendable>: Decodable, Sendable {
    let value: Item?

    init(from decoder: any Decoder) throws {
        value = try? Item(from: decoder)
    }
}

private struct CronJobsAnswer: Decodable, Sendable {
    let jobs: [CronJob]

    init(from decoder: any Decoder) throws {
        if let rows = try? decoder.singleValueContainer().decode([CronLossy<CronJob>].self) {
            jobs = rows.compactMap(\.value)
        } else {
            let keyed = try decoder.container(keyedBy: CronEnvelopeKey.self)
            jobs = try keyed.decode([CronLossy<CronJob>].self, forKey: .jobs).compactMap(\.value)
        }
    }
}

private struct CronJobAnswer: Decodable, Sendable {
    let job: CronJob

    init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CronEnvelopeKey.self), keyed.contains(.job) {
            job = try keyed.decode(CronJob.self, forKey: .job)
        } else {
            job = try CronJob(from: decoder)
        }
    }
}

private struct CronRunsAnswer: Decodable, Sendable {
    let runs: [CronRun]

    init(from decoder: any Decoder) throws {
        if let rows = try? decoder.singleValueContainer().decode([CronLossy<CronRun>].self) {
            runs = rows.compactMap(\.value)
        } else {
            let keyed = try decoder.container(keyedBy: CronEnvelopeKey.self)
            runs = try keyed.decode([CronLossy<CronRun>].self, forKey: .runs).compactMap(\.value)
        }
    }
}

private struct CronTargetsAnswer: Decodable, Sendable {
    let targets: [CronDeliveryTarget]

    init(from decoder: any Decoder) throws {
        if let rows = try? decoder.singleValueContainer().decode([CronLossy<CronDeliveryTarget>].self) {
            targets = rows.compactMap(\.value)
        } else {
            let keyed = try decoder.container(keyedBy: CronEnvelopeKey.self)
            targets = try keyed.decode([CronLossy<CronDeliveryTarget>].self, forKey: .targets).compactMap(\.value)
        }
    }
}

/// The part of `GET /api/config` the cron preview needs. Other keys are ignored.
private struct CronConfigAnswer: Decodable, Sendable {
    let timezone: String?
}

/// Percent-encodes each part of a path. Job ids come from the server, so they are not trusted to be URL-safe.
private func cronPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

/// The `profile` query item for a call that names one. Nil leaves the call scoped to the active profile.
private func profileQuery(_ profile: String?) -> [URLQueryItem] {
    profile.map { [URLQueryItem(name: "profile", value: $0)] } ?? []
}

// MARK: - Cron jobs

extension RESTClient {
    /// `GET /api/cron/jobs?profile=all`: the jobs of every profile, each annotated with its profile. The list is not
    /// scoped to the active profile, because the bots are the profiles.
    public func cronJobs() async throws -> [CronJob] {
        let answer: CronJobsAnswer = try await get(
            "/api/cron/jobs", query: [URLQueryItem(name: "profile", value: "all")])
        return answer.jobs
    }

    /// `GET /api/cron/jobs/{job_id}`, in `profile`, which should be the job's own profile (the list row names it). Nil
    /// reads the active profile.
    public func cronJob(id: String, profile: String? = nil) async throws -> CronJob {
        let answer: CronJobAnswer = try await get("/api/cron/jobs/" + cronPath(id), query: profileQuery(profile))
        return answer.job
    }

    /// `POST /api/cron/jobs`, in `profile` (the active profile when nil). A schedule that is not a 5-field cron
    /// expression is refused here, before anything is sent. Reload the list afterwards to see the new job.
    public func createCronJob(_ job: CronJobCreate, profile: String? = nil) async throws {
        if let problem = CronExpression.validate(job.schedule) { throw problem }
        _ = try await sendRaw("POST", "/api/cron/jobs", query: profileQuery(profile), body: job)
    }

    /// `PUT /api/cron/jobs/{job_id}`, in `profile` (the active profile when nil). Changes the fields in `update` and
    /// leaves the rest as they are. A schedule that is not a 5-field cron expression is refused before anything is
    /// sent.
    public func updateCronJob(id: String, _ update: CronJobUpdate, profile: String? = nil) async throws {
        if case .string(let schedule)? = update.updates["schedule"], let problem = CronExpression.validate(schedule) {
            throw problem
        }
        _ = try await sendRaw("PUT", "/api/cron/jobs/" + cronPath(id), query: profileQuery(profile), body: update)
    }

    /// `DELETE /api/cron/jobs/{job_id}`, in `profile` (the active profile when nil). Cannot be undone.
    public func deleteCronJob(id: String, profile: String? = nil) async throws {
        _ = try await sendRaw("DELETE", "/api/cron/jobs/" + cronPath(id), query: profileQuery(profile))
    }

    /// `POST /api/cron/jobs/{job_id}/pause`, in `profile` (the active profile when nil).
    public func pauseCronJob(id: String, profile: String? = nil) async throws {
        _ = try await sendRaw("POST", "/api/cron/jobs/" + cronPath(id, "pause"), query: profileQuery(profile))
    }

    /// `POST /api/cron/jobs/{job_id}/resume`, in `profile` (the active profile when nil).
    public func resumeCronJob(id: String, profile: String? = nil) async throws {
        _ = try await sendRaw("POST", "/api/cron/jobs/" + cronPath(id, "resume"), query: profileQuery(profile))
    }

    /// `POST /api/cron/jobs/{job_id}/trigger`, in `profile` (the active profile when nil): runs the job now, outside
    /// its schedule.
    public func triggerCronJob(id: String, profile: String? = nil) async throws {
        _ = try await sendRaw("POST", "/api/cron/jobs/" + cronPath(id, "trigger"), query: profileQuery(profile))
    }

    /// `GET /api/cron/jobs/{job_id}/runs`, in `profile` (the active profile when nil), at most `limit` past runs,
    /// newest first.
    public func cronJobRuns(id: String, limit: Int = 20, profile: String? = nil) async throws -> [CronRun] {
        let answer: CronRunsAnswer = try await get(
            "/api/cron/jobs/" + cronPath(id, "runs"),
            query: [URLQueryItem(name: "limit", value: String(limit))] + profileQuery(profile))
        return answer.runs
    }

    /// `GET /api/cron/delivery-targets`: the values a job's `deliver` field can take.
    public func cronDeliveryTargets() async throws -> [CronDeliveryTarget] {
        let answer: CronTargetsAnswer = try await get("/api/cron/delivery-targets")
        return answer.targets
    }

    /// `GET /api/config?profile=`: the time zone a profile's cron schedules are counted in, as an IANA name. `""`
    /// means the server's own local time. Nil `profile` reads the active profile.
    public func serverTimeZone(profile: String? = nil) async throws -> String {
        let answer: CronConfigAnswer = try await get("/api/config", query: profileQuery(profile))
        return answer.timezone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
