import Foundation

/// The periods the Usage screen offers. The server clamps `days` to 1 to 365.
public enum ServerAnalyticsWindow: Int, Sendable, Equatable, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    /// Identity for pickers.
    public var id: Int { rawValue }

    /// Name to show.
    public var title: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        }
    }
}

/// Reads totals and per-model groups out of `GET /api/analytics/usage` and `/api/analytics/models`. Neither answer
/// is typed in the OpenAPI, so this shows the scalar fields as totals and every array of objects as groups.
public enum ServerAnalyticsRows {
    /// The top-level figures: every field that is not a list. Nested objects are flattened.
    public static func totals(from json: JSONValue) -> [ServerStatsRow] {
        guard case .object(let fields) = json else { return ServerStatsRows.rows(from: json) }
        let figures = fields.filter { entry in
            if case .array = entry.value { return false }
            return true
        }
        return ServerStatsRows.rows(from: .object(figures))
    }

    /// One group of rows per object in the first array of objects, such as one per model.
    public static func groups(from json: JSONValue) -> [[ServerStatsRow]] {
        let items: [JSONValue]
        switch json {
        case .array(let list):
            items = list
        case .object(let fields):
            items = firstListOfObjects(fields)
        default:
            items = []
        }
        return items.compactMap { item in
            guard case .object(let fields) = item else { return nil }
            return ServerStatsRows.rows(from: .object(fields), depth: 1)
        }
    }

    private static func firstListOfObjects(_ fields: [String: JSONValue]) -> [JSONValue] {
        for key in fields.keys.sorted() {
            guard case .array(let items)? = fields[key] else { continue }
            if items.contains(where: { if case .object = $0 { return true } else { return false } }) {
                return items
            }
        }
        return []
    }
}
