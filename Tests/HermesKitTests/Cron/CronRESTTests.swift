import Foundation
import HermesKit
import Testing

/// The cron jobs of the shared `cron_jobs` fixture, read through the REST client.
func cronFixtureJobs() async throws -> [CronJob] {
    let http = FakeHTTP()
    http.enqueue(200, try restFixture("cron_jobs"))
    return try await makeClient(http).cronJobs()
}

private func jsonBody(_ request: HTTPRequest?) -> [String: Any]? {
    request?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

@Suite struct CronRESTTests {
    @Test func listReadsEveryProfileAndDecodesTheRows() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("cron_jobs"))
        let jobs = try await makeClient(http, profile: "ops").cronJobs()
        #expect(jobs.map(\.id) == ["9c1f0a2e5b7d", "4b8e6d1a0c93", "e27a9c4f1b06"])
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/cron/jobs")
        #expect(request.url.query == "profile=all", "the list spans every profile, whatever the active one is")
        let first = try #require(jobs.first)
        #expect(first.displayName == "Morning summary" && first.botName == "ana" && first.isEnabled)
        #expect(first.profile == "ana" && first.isDefaultProfile == false)
        #expect(first.schedule?.cronExpression == "0 9 * * 1-5")
        #expect(first.schedule?.summary == CronExpression.describe("0 9 * * 1-5"))
        #expect(first.nextRun != nil && first.lastRun != nil && first.lastStatus == "ok")
        #expect(first.prompt == "Summarise yesterday's chats and list open approvals." && first.deliver == "local")
        let system = jobs[1]
        #expect(system.botName == nil && system.displayName == "Nightly backup check")
        #expect(system.lastError == "backup.log not found" && system.isDefaultProfile == true)
        let paused = jobs[2]
        #expect(!paused.isEnabled && paused.nextRun == nil && paused.pausedReason == "Paused by user")
        #expect(paused.botName == "bo" && paused.schedule?.kind == "interval")
        #expect(paused.schedule?.cronExpression == nil && paused.schedule?.summary == "every 30m")
    }

    @Test func listReadsBareArraysAndSkipsRowsThatDoNotDecode() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"[{"id":"a","name":"x"}, {"name":"no id"}, {"job_id":"b","schedule":"0 9 * * *"}]"#)
        let jobs = try await makeClient(http).cronJobs()
        #expect(jobs.map(\.id) == ["a", "b"])
        #expect(jobs[1].schedule?.cronExpression == "0 9 * * *")
        #expect(http.requests.first?.url.query == "profile=all")
    }

    @Test func singleJobReadsTheBareRecordAndTheWrappedForm() async throws {
        let bare = FakeHTTP()
        bare.enqueue(200, try restFixture("cron_job"))
        bare.enqueue(200, try restFixture("cron_job"))
        let client = makeClient(bare, profile: "ops")
        let job = try await client.cronJob(id: "9c1f0a2e5b7d")
        #expect(job.prompt == "Summarise yesterday's chats and list open approvals.")
        #expect(job.schedule?.expr == "0 9 * * 1-5")
        #expect(job.profile == nil, "a single read is not annotated with its profile")
        let request = try #require(bare.requests.first)
        #expect(request.url.path == "/api/cron/jobs/9c1f0a2e5b7d" && request.url.query == "profile=ops")
        _ = try await client.cronJob(id: "9c1f0a2e5b7d", profile: "bo")
        #expect(bare.requests.last?.url.query == "profile=bo", "a job is read in the profile its list row names")
        let wrapped = FakeHTTP()
        wrapped.enqueue(200, #"{"job": {"id":"z","name":"Ping","schedule":{"kind":"cron","expr":"*/5 * * * *"}}}"#)
        let other = try await makeClient(wrapped).cronJob(id: "z")
        #expect(other.id == "z" && other.schedule?.cronExpression == "*/5 * * * *" && other.isEnabled)
    }

    @Test func writesSendTheRightMethodPathBodyAndProfile() async throws {
        let http = FakeHTTP()
        for _ in 0..<6 { http.enqueue(200) }
        let client = makeClient(http, profile: "ops")
        try await client.createCronJob(
            CronJobCreate(schedule: "0 9 * * *", name: "Summary", prompt: "Summarise", paused: false), profile: "ana")
        try await client.updateCronJob(
            id: "a/b c", CronJobUpdate(name: "Renamed", schedule: "0 10 * * *"), profile: "bo")
        try await client.pauseCronJob(id: "j1", profile: "bo")
        try await client.resumeCronJob(id: "j1", profile: "bo")
        try await client.triggerCronJob(id: "j1", profile: "bo")
        try await client.deleteCronJob(id: "j1", profile: "bo")
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "PUT", "POST", "POST", "POST", "DELETE"])
        #expect(
            requests.map(\.url.path) == [
                "/api/cron/jobs", "/api/cron/jobs/a%2Fb%20c", "/api/cron/jobs/j1/pause", "/api/cron/jobs/j1/resume",
                "/api/cron/jobs/j1/trigger", "/api/cron/jobs/j1",
            ])
        #expect(requests[0].url.query == "profile=ana", "a new job goes to the profile the editor chose")
        #expect(
            requests.dropFirst().allSatisfy { $0.url.query == "profile=bo" },
            "a job's calls go to its own profile, not the active one")
        let created = try #require(jsonBody(requests[0]))
        #expect(created["name"] as? String == "Summary" && created["prompt"] as? String == "Summarise")
        #expect(created["schedule"] as? String == "0 9 * * *" && created["paused"] as? Bool == false)
        #expect(created["deliver"] == nil, "unset fields are left out")
        let updated = try #require(jsonBody(requests[1]))
        #expect((updated["updates"] as? [String: String]) == ["name": "Renamed", "schedule": "0 10 * * *"])
        #expect(requests[2].body == nil && requests[4].body == nil)
    }

    @Test func aCreateWithoutAProfileStaysOnTheActiveOne() async throws {
        let http = FakeHTTP()
        http.enqueue(200)
        try await makeClient(http, profile: "ops").createCronJob(
            CronJobCreate(schedule: "*/5 * * * *", name: "Ping"))
        #expect(http.requests.first?.url.query == "profile=ops")
    }

    @Test func aScheduleThatIsNotFiveFieldCronIsNeverSent() async throws {
        let http = FakeHTTP()
        let client = makeClient(http)
        do {
            try await client.createCronJob(CronJobCreate(schedule: "30m", name: "x", prompt: "y"))
            Issue.record("a bare duration was sent")
        } catch {
            #expect(error is CronParseError)
        }
        do {
            try await client.updateCronJob(id: "j1", CronJobUpdate(schedule: "in 30m"))
            Issue.record("a one-shot delay was sent")
        } catch {
            #expect(error is CronParseError)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func runsReadTheWrapperAndTheEpochStart() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("cron_job_runs"))
        http.enqueue(200, try restFixture("cron_job_runs"))
        let client = makeClient(http)
        let runs = try await client.cronJobRuns(id: "9c1f0a2e5b7d", limit: 5)
        #expect(runs.count == 2)
        #expect(runs[0].title == "COMPLETED · Summary" && runs[0].preview?.hasPrefix("Summary") == true)
        #expect(runs[0].started?.timeIntervalSince1970 == 1_792_141_201)
        #expect(runs[0].ended?.timeIntervalSince1970 == 1_792_141_242 && runs[0].isActive == false)
        #expect(runs[1].title == "FAILED · provider timeout" && runs[1].preview == nil)
        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/cron/jobs/9c1f0a2e5b7d/runs" && request.url.query == "limit=5")
        _ = try await client.cronJobRuns(id: "9c1f0a2e5b7d", limit: 5, profile: "bo")
        #expect(http.requests.last?.url.query == "limit=5&profile=bo")
    }

    @Test func deliveryTargetsReadTheIdAndTheName() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("cron_delivery_targets"))
        let targets = try await makeClient(http).cronDeliveryTargets()
        #expect(targets.map(\.value) == ["local", "telegram:12345"] && targets[1].label == "Telegram chat 12345")
        let bare = FakeHTTP()
        bare.enqueue(200, #"[ "local", {"id":"discord:9","name":"Discord"} ]"#)
        let other = try await makeClient(bare).cronDeliveryTargets()
        #expect(other.map(\.value) == ["local", "discord:9"] && other[1].label == "Discord")
    }

    @Test func serverTimeZoneReadsTheProfileConfig() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"model": "x", "timezone": "Europe/London"}"#)
        http.enqueue(200, #"{"timezone": ""}"#)
        let client = makeClient(http)
        let london = try await client.serverTimeZone(profile: "ana")
        let local = try await client.serverTimeZone()
        #expect(london == "Europe/London" && local.isEmpty)
        #expect(http.requests[0].url.path == "/api/config" && http.requests[0].url.query == "profile=ana")
        #expect(http.requests[1].url.query == nil)
    }

    @Test func cronChangedIsTheRefreshSignal() {
        let changed = GatewayClientEvent.event(
            GatewayEventEnvelope(sessionID: "", seq: nil, event: .cronChanged), replayed: false)
        #expect(CronChangeSignal.isChange(changed))
        let sessions = GatewayClientEvent.event(
            GatewayEventEnvelope(sessionID: "", seq: nil, event: .sessionsChanged), replayed: false)
        #expect(!CronChangeSignal.isChange(sessions))
        #expect(!CronChangeSignal.isChange(.serverRestarted))
    }

    @Test func timestampsReadIsoTimesWithAndWithoutZones() {
        let utc = CronTimestamp.date(from: "2026-10-19T09:00:00Z")
        #expect(utc != nil)
        #expect(utc == CronTimestamp.date(from: "2026-10-19T09:00:00.000Z"))
        #expect(utc == CronTimestamp.date(from: "2026-10-19T11:00:00+02:00"))
        #expect(CronTimestamp.date(from: "2026-10-19T09:00:00") != nil)
        #expect(CronTimestamp.date(from: nil) == nil && CronTimestamp.date(from: "") == nil)
        #expect(CronTimestamp.date(from: "soon") == nil)
    }
}
