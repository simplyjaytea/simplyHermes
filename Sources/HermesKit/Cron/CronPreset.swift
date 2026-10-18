import Foundation

/// The schedules the editor offers without typing cron (plan Q36). Each one is a 5-field expression built from a time.
public enum CronPreset: String, CaseIterable, Identifiable, Sendable, Hashable {
    /// Minute 0 of every hour.
    case hourly
    /// Every day at the chosen time.
    case daily
    /// Monday to Friday at the chosen time.
    case weekdays
    /// One weekday at the chosen time.
    case weekly
    /// One day of the month, 1 to 28, at the chosen time. Days 29 to 31 need raw cron.
    case monthly

    /// Stable identity, the raw name.
    public var id: String { rawValue }

    /// The name in the picker.
    public var title: String {
        switch self {
        case .hourly: "Every hour"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// The 5-field expression for this preset. `hour`, `minute` and `weekday` (0 is Sunday) apply where the preset uses
    /// them; `hourly` ignores the time, `weekly` uses `weekday` and `monthly` uses `dayOfMonth`. Values out of range are
    /// clamped to the nearest valid one.
    public func expression(hour: Int = 9, minute: Int = 0, weekday: Int = 1, dayOfMonth: Int = 1) -> String {
        let clock = "\(min(max(minute, 0), 59)) \(min(max(hour, 0), 23))"
        switch self {
        case .hourly: return "0 * * * *"
        case .daily: return "\(clock) * * *"
        case .weekdays: return "\(clock) * * 1-5"
        case .weekly: return "\(clock) * * \(min(max(weekday, 0), 6))"
        case .monthly: return "\(clock) \(min(max(dayOfMonth, 1), 28)) * *"
        }
    }

    /// The preset and settings that produce exactly `expression`, or nil when no preset does. Reads an existing job's
    /// schedule back into the editor. Text that is valid cron but written differently (`00 9 * * *`) is not a preset.
    public static func matching(_ expression: String) -> CronPresetSettings? {
        let fields = expression.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5, fields[3] == "*" else { return nil }
        let (minuteText, hourText, dayText, weekdayText) = (fields[0], fields[1], fields[2], fields[4])
        let minute = plainNumber(minuteText, upTo: 59)
        let hour = plainNumber(hourText, upTo: 23)
        var candidate: CronPresetSettings?
        if minuteText == "0", hourText == "*", dayText == "*", weekdayText == "*" {
            candidate = CronPresetSettings(preset: .hourly)
        } else if let minute, let hour, dayText == "*" {
            switch weekdayText {
            case "*": candidate = CronPresetSettings(preset: .daily, hour: hour, minute: minute)
            case "1-5": candidate = CronPresetSettings(preset: .weekdays, hour: hour, minute: minute)
            default:
                if let weekday = plainNumber(weekdayText, upTo: 6) {
                    candidate = CronPresetSettings(preset: .weekly, hour: hour, minute: minute, weekday: weekday)
                }
            }
        } else if let minute, let hour, weekdayText == "*", let day = plainNumber(dayText, upTo: 28, from: 1) {
            candidate = CronPresetSettings(preset: .monthly, hour: hour, minute: minute, dayOfMonth: day)
        }
        guard let candidate, candidate.expression == fields.joined(separator: " ") else { return nil }
        return candidate
    }

    /// A number written with digits only, in range.
    private static func plainNumber(_ text: String, upTo highest: Int, from lowest: Int = 0) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text) else { return nil }
        return (lowest...highest).contains(value) ? value : nil
    }
}

/// The settings behind a preset expression, as the editor holds them.
public struct CronPresetSettings: Sendable, Equatable {
    /// The preset.
    public var preset: CronPreset
    /// Hour, 0 to 23.
    public var hour: Int
    /// Minute, 0 to 59.
    public var minute: Int
    /// Weekday for `weekly`, 0 (Sunday) to 6.
    public var weekday: Int
    /// Day of the month for `monthly`, 1 to 28.
    public var dayOfMonth: Int

    /// Creates settings. Only the values the preset uses matter.
    public init(preset: CronPreset, hour: Int = 9, minute: Int = 0, weekday: Int = 1, dayOfMonth: Int = 1) {
        self.preset = preset
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
    }

    /// The 5-field expression these settings produce.
    public var expression: String {
        preset.expression(hour: hour, minute: minute, weekday: weekday, dayOfMonth: dayOfMonth)
    }
}
