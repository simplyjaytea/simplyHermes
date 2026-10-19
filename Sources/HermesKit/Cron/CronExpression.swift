import Foundation

/// Why a cron expression is not valid. ``message`` is the sentence the editor shows.
public enum CronParseError: Error, Sendable, Equatable {
    /// Nothing was entered.
    case empty
    /// The expression does not have five fields. `count` is how many it has.
    case fieldCount(Int)
    /// A field holds text that is not cron syntax.
    case badField(field: String, text: String)
    /// A number is outside the range of its field.
    case outOfRange(field: String, lowest: Int, highest: Int)
    /// A range such as `5-1` runs backwards.
    case backwardsRange(field: String)
    /// A step such as `*/0` is less than 1.
    case badStep(field: String)

    /// The sentence to show.
    public var message: String {
        switch self {
        case .empty:
            "Enter five fields: minute, hour, day of month, month and day of week."
        case .fieldCount(let count):
            "A schedule has five fields: minute, hour, day of month, month and day of week. "
                + "This one has \(count)."
        case .badField(let field, let text):
            "The \(field) \"\(text)\" is not valid. Use numbers, *, lists such as 1,15, "
                + "ranges such as 1-5, or steps such as */10."
        case .outOfRange(let field, let lowest, let highest):
            "The \(field) must be from \(lowest) to \(highest)."
        case .backwardsRange(let field):
            "The \(field) range runs backwards. Put the smaller number first."
        case .badStep(let field):
            "The step in the \(field) must be 1 or more."
        }
    }
}

/// A standard 5-field cron expression: minute, hour, day of month, month and day of week.
///
/// Read the way Vixie cron reads it: `*`, lists (`1,15`), ranges (`1-5`), steps (`*/10`, `0-30/5`, `2/15`), month and
/// day names (`jan`, `mon-fri`), and Sunday as either 0 or 7. When both day fields are restricted, a day runs when
/// either matches. When either one starts with `*`, both must match.
public struct CronExpression: Sendable, Equatable {
    /// The expression as written, with single spaces between the fields.
    public let text: String
    private let minutes: UInt64
    private let hours: UInt64
    private let daysOfMonth: UInt64
    private let months: UInt64
    private let daysOfWeek: UInt64
    private let dayOfMonthIsStar: Bool
    private let dayOfWeekIsStar: Bool

    private static let monthNumbers = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    private static let weekdayNumbers = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
    private static let weekdayTitles = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    /// Parses `text`. Throws ``CronParseError`` with the reason when it is not a valid expression.
    public static func parse(_ text: String) throws(CronParseError) -> CronExpression {
        let fields = fields(of: text)
        guard !fields.isEmpty else { throw CronParseError.empty }
        guard fields.count == 5 else { throw CronParseError.fieldCount(fields.count) }
        return CronExpression(
            text: fields.joined(separator: " "),
            minutes: try mask(fields[0], name: "minute", range: 0...59, names: [:]),
            hours: try mask(fields[1], name: "hour", range: 0...23, names: [:]),
            daysOfMonth: try mask(fields[2], name: "day of month", range: 1...31, names: [:]),
            months: try mask(fields[3], name: "month", range: 1...12, names: monthNumbers),
            daysOfWeek: foldingSunday(try mask(fields[4], name: "day of week", range: 0...7, names: weekdayNumbers)),
            dayOfMonthIsStar: fields[2].hasPrefix("*"),
            dayOfWeekIsStar: fields[4].hasPrefix("*"))
    }

    /// The reason `text` is not a valid expression, or nil when it is one.
    public static func validate(_ text: String) -> CronParseError? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error
        }
    }

    /// The next `count` times the schedule runs, strictly after `date`, oldest first, in `calendar`'s time zone. It looks
    /// five years ahead, so a schedule that never runs (such as February 30) returns fewer runs.
    public func nextRuns(after date: Date, count: Int, calendar: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        let horizon = calendar.date(byAdding: .year, value: 5, to: date) ?? date
        var runs: [Date] = []
        var day = calendar.startOfDay(for: date)
        while day <= horizon, runs.count < count {
            if matchesDay(day, calendar: calendar) {
                appendRuns(on: day, after: date, count: count, calendar: calendar, into: &runs)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return runs
    }

    /// The schedule in plain words, such as `Every day at 09:00`. A schedule this does not recognise comes back as
    /// `Custom: <text>`, and a missing one as `No schedule`.
    public static func describe(_ schedule: String?) -> String {
        let text = fields(of: schedule ?? "").joined(separator: " ")
        guard !text.isEmpty else { return "No schedule" }
        guard validate(text) == nil else { return "Custom: \(text)" }
        return plainWords(fields(of: text)) ?? "Custom: \(text)"
    }

    // MARK: - Matching

    private func matchesDay(_ day: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        guard let month = parts.month, let dayOfMonth = parts.day, let weekday = parts.weekday else { return false }
        guard (months & Self.bit(month)) != 0 else { return false }
        let dayOfMonthMatches = (daysOfMonth & Self.bit(dayOfMonth)) != 0
        // Calendar numbers weekdays from 1 (Sunday); cron numbers them from 0 (Sunday).
        let dayOfWeekMatches = (daysOfWeek & Self.bit(weekday - 1)) != 0
        if dayOfMonthIsStar || dayOfWeekIsStar {
            return dayOfMonthMatches && dayOfWeekMatches
        }
        return dayOfMonthMatches || dayOfWeekMatches
    }

    private func appendRuns(on day: Date, after date: Date, count: Int, calendar: Calendar, into runs: inout [Date]) {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        for hour in 0...23 where (hours & Self.bit(hour)) != 0 {
            for minute in 0...59 where (minutes & Self.bit(minute)) != 0 {
                guard runs.count < count else { return }
                let clock = DateComponents(
                    year: parts.year, month: parts.month, day: parts.day, hour: hour, minute: minute)
                guard let run = calendar.date(from: clock), run > date else { continue }
                if let last = runs.last, run <= last { continue }
                runs.append(run)
            }
        }
    }

    // MARK: - Parsing

    private static func fields(of text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).map(String.init)
    }

    /// What a field's values are checked against: its name, the text it was written as, the values it allows and the
    /// names it accepts.
    private struct CronField {
        let name: String
        let text: String
        let range: ClosedRange<Int>
        let names: [String: Int]
    }

    /// The set of values a field allows, as one bit per value.
    private static func mask(
        _ text: String, name: String, range: ClosedRange<Int>, names: [String: Int]
    ) throws(CronParseError) -> UInt64 {
        let field = CronField(name: name, text: text, range: range, names: names)
        var result: UInt64 = 0
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = item.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { throw CronParseError.badField(field: name, text: text) }
            var step = 1
            if pieces.count == 2 {
                guard let value = digits(pieces[1]) else { throw CronParseError.badField(field: name, text: text) }
                guard value >= 1 else { throw CronParseError.badStep(field: name) }
                step = value
            }
            let (lowest, highest) = try bounds(pieces[0], stepped: pieces.count == 2, field: field)
            for value in stride(from: lowest, through: highest, by: step) {
                result |= bit(value)
            }
        }
        return result
    }

    /// The first and last value of one list item: `*`, `5`, `1-5`, or `5` with a step, which runs to the end.
    private static func bounds(
        _ spread: Substring, stepped: Bool, field: CronField
    ) throws(CronParseError) -> (Int, Int) {
        if spread == "*" { return (field.range.lowerBound, field.range.upperBound) }
        let ends = spread.split(separator: "-", omittingEmptySubsequences: false)
        switch ends.count {
        case 1:
            guard let value = number(ends[0], names: field.names) else {
                throw CronParseError.badField(field: field.name, text: field.text)
            }
            try checkRange(value, field.range, name: field.name)
            return (value, stepped ? field.range.upperBound : value)
        case 2:
            guard let low = number(ends[0], names: field.names), let high = number(ends[1], names: field.names) else {
                throw CronParseError.badField(field: field.name, text: field.text)
            }
            try checkRange(low, field.range, name: field.name)
            try checkRange(high, field.range, name: field.name)
            guard low <= high else { throw CronParseError.backwardsRange(field: field.name) }
            return (low, high)
        default:
            throw CronParseError.badField(field: field.name, text: field.text)
        }
    }

    private static func checkRange(_ value: Int, _ range: ClosedRange<Int>, name: String) throws(CronParseError) {
        guard range.contains(value) else {
            throw CronParseError.outOfRange(field: name, lowest: range.lowerBound, highest: range.upperBound)
        }
    }

    private static func number<Text: StringProtocol>(_ text: Text, names: [String: Int]) -> Int? {
        digits(text) ?? names[text.lowercased()]
    }

    private static func digits<Text: StringProtocol>(_ text: Text) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// Sunday written as 7 is the same day as 0.
    private static func foldingSunday(_ mask: UInt64) -> UInt64 {
        guard (mask & bit(7)) != 0 else { return mask }
        return (mask | bit(0)) & ~bit(7)
    }

    private static func bit(_ value: Int) -> UInt64 {
        UInt64(1) << UInt64(value)
    }

    // MARK: - Plain words

    private static func plainWords(_ parts: [String]) -> String? {
        let (minute, hour, dayOfMonth, month, weekday) = (parts[0], parts[1], parts[2], parts[3], parts[4])
        guard month == "*" else { return nil }
        if dayOfMonth == "*", weekday == "*", let words = repeatingWords(minute: minute, hour: hour) {
            return words
        }
        return clockWords(minute: minute, hour: hour, dayOfMonth: dayOfMonth, weekday: weekday)
    }

    /// Words for a schedule that repeats within the day.
    private static func repeatingWords(minute: String, hour: String) -> String? {
        if hour == "*" {
            if minute == "*" { return "Every minute" }
            if let step = stepValue(minute) { return step == 1 ? "Every minute" : "Every \(step) minutes" }
            if let mark = digits(minute) { return mark == 0 ? "Every hour" : "Every hour at :\(twoDigits(mark))" }
            return nil
        }
        guard let every = stepValue(hour), let mark = digits(minute) else { return nil }
        let base = every == 1 ? "Every hour" : "Every \(every) hours"
        return mark == 0 ? base : "\(base) at :\(twoDigits(mark))"
    }

    /// Words for a schedule that runs at a clock time on the days its day fields pick.
    private static func clockWords(minute: String, hour: String, dayOfMonth: String, weekday: String) -> String? {
        guard let hourValue = digits(hour), let minuteValue = digits(minute) else { return nil }
        let clock = "\(twoDigits(hourValue)):\(twoDigits(minuteValue))"
        if dayOfMonth == "*" {
            switch weekday {
            case "*": return "Every day at \(clock)"
            case "1-5": return "Weekdays at \(clock)"
            case "0,6", "6,0": return "Weekends at \(clock)"
            default:
                guard let day = digits(weekday), day <= 7 else { return nil }
                return "Every \(weekdayTitles[day % 7]) at \(clock)"
            }
        }
        if weekday == "*", let day = digits(dayOfMonth) {
            return "Day \(day) of every month at \(clock)"
        }
        return nil
    }

    /// The N in `*/N`, or nil for any other text.
    private static func stepValue(_ text: String) -> Int? {
        guard text.hasPrefix("*/") else { return nil }
        return digits(text.dropFirst(2))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
