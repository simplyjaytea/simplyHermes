import Foundation
import HermesKit
import Testing

@Suite struct CronScheduleTests {
    /// A job that carries only a schedule, so the schedule is read the way the list reads it.
    private struct Holder: Decodable {
        let schedule: CronSchedule
    }

    private func schedule(_ json: String) throws -> CronSchedule {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Holder.self, from: Data("{\"schedule\": \(json)}".utf8)).schedule
    }

    @Test func readsTheServersObjectForEachKind() throws {
        let cron = try schedule(#"{"kind":"cron","expr":"0 9 * * 1-5","display":"0 9 * * 1-5"}"#)
        #expect(cron.kind == "cron" && cron.cronExpression == "0 9 * * 1-5")
        #expect(cron.summary == CronExpression.describe("0 9 * * 1-5"))
        let once = try schedule(#"{"kind":"once","run_at":"2026-10-19T09:00:00+00:00","display":"once in 30m"}"#)
        #expect(once.runAt == "2026-10-19T09:00:00+00:00" && once.cronExpression == nil)
        #expect(once.summary == "once in 30m")
        let interval = try schedule(#"{"kind":"interval","minutes":30,"display":"every 30m"}"#)
        #expect(interval.minutes == 30 && interval.cronExpression == nil && interval.summary == "every 30m")
    }

    @Test func readsABareStringAsItsText() throws {
        let text = try schedule(#""0 9 * * *""#)
        #expect(text.cronExpression == "0 9 * * *")
        let duration = try schedule(#""30m""#)
        #expect(duration.cronExpression == nil, "a bare duration is a recurring interval, never cron")
        #expect(duration.summary == CronExpression.describe("30m"))
    }

    @Test func aSixFieldOrMissingExpressionIsNotEditable() {
        #expect(CronSchedule(kind: "cron", expr: "0 0 9 * * *").cronExpression == nil)
        #expect(CronSchedule(kind: "cron").cronExpression == nil)
        #expect(CronSchedule().summary == "No schedule")
        #expect(CronSchedule(kind: "interval", minutes: 120).summary == "Every 120 minutes")
    }
}
