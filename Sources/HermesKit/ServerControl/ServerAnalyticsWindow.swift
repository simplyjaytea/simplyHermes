import Foundation

/// The periods the Usage screen offers. The recorded answers carry `period_days`
/// (Fixtures/rest/GET_api_analytics_usage.json and GET_api_analytics_models.json). The spec's `days` takes 1 to 365
/// (docs/protocol/dashboard-openapi.json).
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

/// Reads totals and per-model groups out of `GET /api/analytics/usage` and `/api/analytics/models`. Neither answer is
/// typed in the OpenAPI. The totals are the answer's fields that are not lists, shown as rows. The groups are the
/// objects of the per-model list: `models` (GET_api_analytics_models.json) or `by_model`
/// (GET_api_analytics_usage.json). No other list is shown.
public enum ServerAnalyticsRows {
    /// The per-model list names, in the order they are tried.
    private static let groupKeys = ["models", "by_model"]

    /// The top-level figures: every field that is not a list. Nested objects are flattened.
    public static func totals(from json: JSONValue) -> [ServerStatsRow] {
        guard case .object(let fields) = json else { return ServerStatsRows.rows(from: json) }
        let figures = fields.filter { entry in
            if case .array = entry.value { return false }
            return true
        }
        return ServerStatsRows.rows(from: .object(figures))
    }

    /// One group of rows per object in the per-model list. A top-level list is grouped as it is.
    public static func groups(from json: JSONValue) -> [[ServerStatsRow]] {
        let items: [JSONValue]
        switch json {
        case .array(let list):
            items = list
        case .object(let fields):
            let lists = groupKeys.compactMap { key -> [JSONValue]? in
                guard case .array(let list)? = fields[key] else { return nil }
                return list
            }
            items = lists.first ?? []
        default:
            items = []
        }
        return items.compactMap { item in
            guard case .object(let fields) = item else { return nil }
            return ServerStatsRows.rows(from: .object(fields), depth: 1)
        }
    }
}
