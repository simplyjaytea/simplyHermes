import Foundation
import Testing

@testable import HermesKit

@Suite struct SessionGroupingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Thursday 2026-10-15 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_076_400)

    private func session(_ id: String, hoursAgo: Double?, pinned: Bool = false) throws -> SessionRecord {
        var json = #"{"id":"\#(id)""#
        if let hoursAgo { json += #","lastActivityAt":\#(now.timeIntervalSince1970 - hoursAgo * 3600)"# }
        if pinned { json += #","pinned":true"# }
        return try JSONDecoder().decode(SessionRecord.self, from: Data((json + "}").utf8))
    }

    private func ids(_ sections: [SessionSection]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.group.rawValue, $0.sessions.map(\.id)) })
    }

    @Test func groupsByDayWithPinnedFirst() throws {
        let sessions = [
            try session("old", hoursAgo: 24 * 40), try session("today", hoursAgo: 2),
            try session("pin", hoursAgo: 24 * 90, pinned: true), try session("yest", hoursAgo: 20),
            try session("week", hoursAgo: 24 * 4),
        ]
        let sections = SessionGrouping.sections(sessions, now: now, calendar: calendar)
        #expect(sections.map(\.group) == [.pinned, .today, .yesterday, .lastWeek, .earlier])
        #expect(
            ids(sections) == [
                "pinned": ["pin"], "today": ["today"], "yesterday": ["yest"], "lastWeek": ["week"], "earlier": ["old"],
            ])
    }

    @Test func midnightBoundaryIsInTheCalendarsTimeZone() throws {
        // 14h30 before 15:00 is 00:30 today; 15h30 before is 23:30 yesterday.
        let sections = SessionGrouping.sections(
            [try session("after", hoursAgo: 14.5), try session("before", hoursAgo: 15.5)], now: now, calendar: calendar)
        #expect(ids(sections) == ["today": ["after"], "yesterday": ["before"]])
    }

    @Test func eachGroupIsNewestFirstAndStableForTies() throws {
        let sessions = [
            try session("a", hoursAgo: 3), try session("b", hoursAgo: 1), try session("c", hoursAgo: 3),
        ]
        let sections = SessionGrouping.sections(sessions, now: now, calendar: calendar)
        #expect(ids(sections)["today"] == ["b", "a", "c"])
    }

    @Test func sessionsWithoutATimeGoToEarlierLast() throws {
        let sections = SessionGrouping.sections(
            [try session("none", hoursAgo: nil), try session("dated", hoursAgo: 24 * 30)], now: now, calendar: calendar)
        #expect(ids(sections)["earlier"] == ["dated", "none"])
    }

    @Test func emptySectionsAreLeftOut() throws {
        #expect(SessionGrouping.sections([], now: now, calendar: calendar).isEmpty)
        let sections = SessionGrouping.sections([try session("t", hoursAgo: 1)], now: now, calendar: calendar)
        #expect(sections.map(\.group) == [.today])
    }

    @Test func rowTimeReadsLikeMessages() throws {
        let locale = Locale(identifier: "en_GB")
        func label(_ hours: Double) throws -> String? {
            SessionGrouping.rowTime(try session("x", hoursAgo: hours), now: now, calendar: calendar, locale: locale)
        }
        #expect(try label(1)?.contains("14") == true)
        #expect(try label(20) == "Yesterday")
        #expect(try label(24 * 3) == "Monday")
        #expect(try label(24 * 40)?.contains("Sep") == true)
        #expect(SessionGrouping.rowTime(try session("n", hoursAgo: nil), now: now, calendar: calendar) == nil)
    }
}
