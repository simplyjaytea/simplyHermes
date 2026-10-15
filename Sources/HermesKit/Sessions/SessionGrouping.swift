import Foundation

/// A section of the sessions list.
public enum SessionGroup: String, Sendable, CaseIterable, Identifiable {
    /// Sessions the user pinned.
    case pinned
    /// Active since midnight.
    case today
    /// Active yesterday.
    case yesterday
    /// Active in the 6 days before yesterday.
    case lastWeek
    /// Anything older, or with no known time.
    case earlier

    /// The section id, for `ForEach`.
    public var id: String { rawValue }

    /// The header text.
    public var title: String {
        switch self {
        case .pinned: "Pinned"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .lastWeek: "Previous 7 days"
        case .earlier: "Earlier"
        }
    }
}

/// One section with its sessions, in display order.
public struct SessionSection: Sendable, Equatable, Identifiable {
    /// Which group.
    public var group: SessionGroup
    /// The sessions, newest first.
    public var sessions: [SessionRecord]

    /// The group id, for `ForEach`.
    public var id: String { group.id }
}

/// Groups sessions by time for the sessions list: pinned first, then by recency.
public enum SessionGrouping {
    /// Groups `sessions`. Empty sections are left out. Archived and hidden sessions are kept: filter them first.
    ///
    /// - Parameters:
    ///   - sessions: The sessions, in any order.
    ///   - now: The current time.
    ///   - calendar: Decides where a day starts. Defaults to the user's calendar.
    public static func sections(
        _ sessions: [SessionRecord], now: Date = Date(), calendar: Calendar = .current
    ) -> [SessionSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday
        func group(_ session: SessionRecord) -> SessionGroup {
            if session.pinned?.value == true { return .pinned }
            guard let time = activity(session) else { return .earlier }
            let date = Date(timeIntervalSince1970: time)
            if date >= startOfToday { return .today }
            if date >= startOfYesterday { return .yesterday }
            return date >= startOfWeek ? .lastWeek : .earlier
        }
        let ordered = sessions.enumerated().sorted { left, right in
            let (a, b) = (activity(left.element) ?? -.infinity, activity(right.element) ?? -.infinity)
            return a == b ? left.offset < right.offset : a > b
        }.map(\.element)
        let grouped = Dictionary(grouping: ordered, by: group)
        return SessionGroup.allCases.compactMap { group in
            grouped[group].map { SessionSection(group: group, sessions: $0) }
        }
    }

    /// The time a session was last active, falling back to when it started.
    public static func activity(_ session: SessionRecord) -> Double? {
        session.lastActivityAt ?? session.startedAt
    }

    /// A short time label for a row: `14:05` today, `Yesterday`, a weekday within a week, else a date.
    public static func rowTime(
        _ session: SessionRecord, now: Date = Date(), calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let time = activity(session) else { return nil }
        let date = Date(timeIntervalSince1970: time)
        func format(_ style: Date.FormatStyle) -> String {
            var style = style.locale(locale)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return format(.dateTime.hour().minute()) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        if date >= yesterday { return "Yesterday" }
        let week = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? yesterday
        if date >= week { return format(.dateTime.weekday(.wide)) }
        return format(.dateTime.day().month(.abbreviated))
    }
}
