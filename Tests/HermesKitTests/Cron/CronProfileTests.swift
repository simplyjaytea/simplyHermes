import HermesKit
import Testing

@Suite struct CronProfileTests {
    @Test func aNamedProfileIsABotAndTheDefaultProfileIsSystem() {
        #expect(CronJob(jobId: "1", name: "Summary", profile: "ana").botName == "ana")
        #expect(CronJob(jobId: "2", name: "Backup", profile: "default", isDefaultProfile: true).botName == nil)
        #expect(CronJob(jobId: "3", name: "Backup", profile: "default").botName == nil)
        #expect(CronJob(jobId: "4", name: "Backup").botName == nil)
        #expect(CronJob(jobId: "5", name: "Backup", profile: "  ").botName == nil)
        #expect(CronJob(jobId: "6", name: "Backup", profile: " bo ").botName == "bo")
        #expect(CronJob(jobId: "7", name: "Backup", profile: "bo", isDefaultProfile: true).botName == nil)
    }

    @Test func aLegacyNameIsShownAsStored() {
        let legacy = CronJob(jobId: "8", name: "[bot:ana] Morning summary", profile: "ana")
        #expect(legacy.displayName == "[bot:ana] Morning summary" && legacy.botName == "ana")
        #expect(CronJob(jobId: "9", prompt: "First line\nSecond line").displayName == "First line")
        #expect(CronJob(jobId: "10", name: "  ").displayName == "Untitled automation")
    }

    @Test func jobsFromTheFixtureSplitIntoBotsAndSystem() async throws {
        let jobs = try await cronFixtureJobs()
        #expect(jobs.map(\.botName) == ["ana", nil, "bo"])
        #expect(CronJobFilter.bots.includes(jobs[0]) && CronJobFilter.bots.includes(jobs[2]))
        #expect(!CronJobFilter.bots.includes(jobs[1]))
        #expect(CronJobFilter.system.includes(jobs[1]) && !CronJobFilter.system.includes(jobs[0]))
        #expect(CronJobFilter.all.includes(jobs[1]) && CronJobFilter.all.includes(jobs[2]))
        #expect(CronJobFilter.bot("bo").includes(jobs[2]) && !CronJobFilter.bot("bo").includes(jobs[0]))
        #expect(CronJobFilter.chips == [.all, .bots, .system])
        #expect(CronJobFilter.chips.map(\.title) == ["All", "Bots", "System"])
        #expect(CronJobFilter.bot("bo").title == "bo")
    }

    @Test func groupsBotsAlphabeticallyWithSystemLast() {
        let jobs = [
            CronJob(jobId: "1", name: "a", profile: "zed"), CronJob(jobId: "2", name: "backup"),
            CronJob(jobId: "3", name: "b", profile: "Ana"), CronJob(jobId: "4", name: "c", profile: "ana"),
            CronJob(jobId: "5", name: "d", profile: "Bo"),
        ]
        let all = CronJobGrouping.sections(jobs, filter: .all)
        // Names sort without regard to case. The exact spelling breaks the tie between Ana and ana.
        #expect(all.map(\.title) == ["Ana", "ana", "Bo", "zed", "System"])
        #expect(all.first { $0.title == "Ana" }?.jobs.map(\.jobId) == ["3"])
        #expect(all.last?.jobs.map(\.jobId) == ["2"])
        #expect(all.map(\.id).contains("system") && all.first?.id == "bot:Ana")
        #expect(CronJobGrouping.sections(jobs, filter: .bots).map(\.title) == ["Ana", "ana", "Bo", "zed"])
        #expect(CronJobGrouping.sections(jobs, filter: .system).map(\.title) == ["System"])
        #expect(CronJobGrouping.sections(jobs, filter: .bot("Bo")).map(\.title) == ["Bo"])
        #expect(CronJobGrouping.botNames(jobs) == ["Ana", "ana", "Bo", "zed"])
        #expect(CronJobGrouping.sections([], filter: .all).isEmpty)
    }
}
