import Foundation
import HermesKit
import Testing

/// A fixed calendar, so every run time in these tests is deterministic.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite struct CronExpressionTests {
    @Test func parsesEachFieldForm() {
        let accepted = [
            "*/15 9-17 * * 1-5", "0 0 1,15 * *", "5 4 * * sun", "0 12 * jan-jun 7", "30 2 */3 * *",
            "0-59/10 * * * mon,wed,fri", "5/20 * * * *", "0 0 * * 0-7/2", "  0   9 * * *  ",
        ]
        for text in accepted {
            #expect(CronExpression.validate(text) == nil, "\(text) should be valid")
        }
    }

    @Test func rejectsBadFieldsWithAReason() {
        #expect(CronExpression.validate("") == .empty)
        #expect(CronExpression.validate("* * * *") == .fieldCount(4))
        #expect(CronExpression.validate("@daily") == .fieldCount(1))
        #expect(CronExpression.validate("60 * * * *") == .outOfRange(field: "minute", lowest: 0, highest: 59))
        #expect(CronExpression.validate("* 24 * * *") == .outOfRange(field: "hour", lowest: 0, highest: 23))
        #expect(CronExpression.validate("* * 0 * *") == .outOfRange(field: "day of month", lowest: 1, highest: 31))
        #expect(CronExpression.validate("* * * 13 *") == .outOfRange(field: "month", lowest: 1, highest: 12))
        #expect(CronExpression.validate("* * * * 8") == .outOfRange(field: "day of week", lowest: 0, highest: 7))
        #expect(CronExpression.validate("5-1 * * * *") == .backwardsRange(field: "minute"))
        #expect(CronExpression.validate("*/0 * * * *") == .badStep(field: "minute"))
        #expect(CronExpression.validate("1,,2 * * * *") == .badField(field: "minute", text: "1,,2"))
        #expect(CronExpression.validate("a * * * *") == .badField(field: "minute", text: "a"))
        #expect(CronExpression.validate("1- * * * *") == .badField(field: "minute", text: "1-"))
        #expect(CronExpression.validate("1/ * * * *") == .badField(field: "minute", text: "1/"))
        #expect(CronExpression.validate("* * * * mon-fri-sat") == .badField(field: "day of week", text: "mon-fri-sat"))
        #expect(CronExpression.validate("* * * * 1-5").map(\.message) == nil)
    }

    @Test func everyErrorHasASentence() {
        let failures = ["", "* * * *", "61 * * * *", "* * * * 9", "0 0 * * 5-1", "*/0 * * * *"]
        for text in failures {
            let error = CronExpression.validate(text)
            #expect(error != nil && error?.message.isEmpty == false, "\(text) needs a message")
        }
    }

    @Test func stepsAndListsRunAtTheRightMinutes() throws {
        let quarter = try CronExpression.parse("*/15 * * * *")
        #expect(
            quarter.nextRuns(after: utcDate(2026, 10, 18, 10, 7), count: 5, calendar: utc) == [
                utcDate(2026, 10, 18, 10, 15), utcDate(2026, 10, 18, 10, 30), utcDate(2026, 10, 18, 10, 45),
                utcDate(2026, 10, 18, 11, 0), utcDate(2026, 10, 18, 11, 15),
            ])
        let offset = try CronExpression.parse("5/20 * * * *")
        #expect(
            offset.nextRuns(after: utcDate(2026, 10, 18, 10, 0), count: 4, calendar: utc) == [
                utcDate(2026, 10, 18, 10, 5), utcDate(2026, 10, 18, 10, 25), utcDate(2026, 10, 18, 10, 45),
                utcDate(2026, 10, 18, 11, 5),
            ])
        let lists = try CronExpression.parse("0,30 8-9 * * *")
        #expect(
            lists.nextRuns(after: utcDate(2026, 10, 18, 8, 15), count: 3, calendar: utc) == [
                utcDate(2026, 10, 18, 8, 30), utcDate(2026, 10, 18, 9, 0), utcDate(2026, 10, 18, 9, 30),
            ])
    }

    @Test func namesAndSundayAsSevenAreTheSameDays() throws {
        let from = utcDate(2026, 10, 1)
        let names = try CronExpression.parse("0 9 * * MON-FRI").nextRuns(after: from, count: 7, calendar: utc)
        let numbers = try CronExpression.parse("0 9 * * 1-5").nextRuns(after: from, count: 7, calendar: utc)
        #expect(names == numbers && names.count == 7)
        let sevenIsSunday = try CronExpression.parse("0 9 * * 7").nextRuns(after: from, count: 2, calendar: utc)
        let zeroIsSunday = try CronExpression.parse("0 9 * * 0").nextRuns(after: from, count: 2, calendar: utc)
        #expect(sevenIsSunday == zeroIsSunday)
        #expect(sevenIsSunday.first == utcDate(2026, 10, 4, 9))
        let january = try CronExpression.parse("0 0 1 JAN *").nextRuns(after: from, count: 1, calendar: utc)
        #expect(january == [utcDate(2027, 1, 1)])
    }

    @Test func dayOfMonthAndDayOfWeekAreOrWhenBothAreRestricted() throws {
        // The 13th, or any Friday. October 2026: Fridays are the 2nd, 9th and 16th.
        let thirteenthOrFriday = try CronExpression.parse("0 9 13 * 5")
        #expect(
            thirteenthOrFriday.nextRuns(after: utcDate(2026, 10, 1), count: 4, calendar: utc) == [
                utcDate(2026, 10, 2, 9), utcDate(2026, 10, 9, 9), utcDate(2026, 10, 13, 9), utcDate(2026, 10, 16, 9),
            ])
        // The 1st, or any Monday. October 1 2026 is a Thursday and still runs, because the 1st matches.
        let firstOrMonday = try CronExpression.parse("0 9 1 * 1")
        #expect(
            firstOrMonday.nextRuns(after: utcDate(2026, 10, 1), count: 3, calendar: utc) == [
                utcDate(2026, 10, 1, 9), utcDate(2026, 10, 5, 9), utcDate(2026, 10, 12, 9),
            ])
    }

    @Test func aStarInEitherDayFieldMakesBothMatch() throws {
        // Every odd day of the month, and only when that day is a Monday.
        let oddMondays = try CronExpression.parse("0 9 */2 * 1")
        #expect(
            oddMondays.nextRuns(after: utcDate(2026, 10, 1), count: 3, calendar: utc) == [
                utcDate(2026, 10, 5, 9), utcDate(2026, 10, 19, 9), utcDate(2026, 11, 9, 9),
            ])
    }

    @Test func runsAreStrictlyAfterTheStartAndImpossibleSchedulesStop() throws {
        let daily = try CronExpression.parse("0 9 * * *")
        #expect(
            daily.nextRuns(after: utcDate(2026, 10, 18, 9, 0), count: 1, calendar: utc) == [utcDate(2026, 10, 19, 9)])
        #expect(
            daily.nextRuns(after: utcDate(2026, 10, 18, 8, 59), count: 1, calendar: utc) == [utcDate(2026, 10, 18, 9)])
        #expect(daily.nextRuns(after: utcDate(2026, 10, 1), count: 0, calendar: utc).isEmpty)
        let february30 = try CronExpression.parse("0 0 30 2 *")
        #expect(february30.nextRuns(after: utcDate(2026, 10, 1), count: 3, calendar: utc).isEmpty)
    }

    @Test func runsFollowTheTimeZoneOfTheCalendar() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 06:30 in New York is 10:30 UTC while daylight time lasts (until November 1, 2026).
        let morning = try CronExpression.parse("30 6 * * *")
        let runs = morning.nextRuns(after: utcDate(2026, 10, 18, 10, 0), count: 2, calendar: newYork)
        #expect(runs == [utcDate(2026, 10, 18, 10, 30), utcDate(2026, 10, 19, 10, 30)])
    }

    @Test func describesRecognisedSchedulesInPlainWords() {
        #expect(CronExpression.describe("0 9 * * *") == "Every day at 09:00")
        #expect(CronExpression.describe("5 9 * * 1-5") == "Weekdays at 09:05")
        #expect(CronExpression.describe("30 8 * * 3") == "Every Wednesday at 08:30")
        #expect(CronExpression.describe("0 0 1 * *") == "Day 1 of every month at 00:00")
        #expect(CronExpression.describe("0 * * * *") == "Every hour")
        #expect(CronExpression.describe("15 * * * *") == "Every hour at :15")
        #expect(CronExpression.describe("*/10 * * * *") == "Every 10 minutes")
        #expect(CronExpression.describe("0 */2 * * *") == "Every 2 hours")
        #expect(CronExpression.describe("0 9 * * 1,3") == "Custom: 0 9 * * 1,3")
        #expect(CronExpression.describe("0 9 * jan *") == "Custom: 0 9 * jan *")
        #expect(CronExpression.describe("every 2h") == "Custom: every 2h")
        #expect(CronExpression.describe(nil) == "No schedule")
        #expect(CronExpression.describe("   ") == "No schedule")
    }
}
