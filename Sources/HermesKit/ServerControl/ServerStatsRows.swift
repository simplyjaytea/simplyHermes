import Foundation

/// One label and value line on the server-control screens (WP-54).
public struct ServerStatsRow: Sendable, Equatable, Identifiable {
    /// Humanized from the server's key, such as `Cpu percent`. Nested keys join their parent's label.
    public var label: String
    /// The value as text.
    public var value: String

    /// Creates a row.
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    /// Labels are unique within one list, so they identify rows.
    public var id: String { label }
}

/// Turns answers the OpenAPI leaves untyped (`/api/system/stats`, `/api/health/idle`, the update receipt) into
/// rows. The screens show what the server sends and name nothing they have not been told about.
public enum ServerStatsRows {
    /// Flattens an object into label and value rows, sorted by key. Nested objects are flattened to `depth` levels
    /// and arrays show their count. A non-object answer becomes one row.
    public static func rows(from json: JSONValue, depth: Int = 2) -> [ServerStatsRow] {
        guard case .object(let fields) = json else {
            return [ServerStatsRow(label: "Value", value: text(json))]
        }
        return flatten(fields, parent: nil, depth: depth)
    }

    /// The Logs header figures: CPU, memory and disk percent, and uptime, in that order. Each is found by its label,
    /// a flattened key of GET_api_system_stats.json: `cpu_percent`, `memory.percent`, `disk.percent`,
    /// `uptime_seconds`. A label the answer lacks is left out, and no other figure is shown.
    public static func logsHeader(from json: JSONValue) -> [ServerStatsRow] {
        let all = rows(from: json)
        return ["Cpu percent", "Memory percent", "Disk percent", "Uptime seconds"].compactMap { label in
            all.first { $0.label == label }
        }
    }

    /// The value as the screens show it.
    public static func text(_ value: JSONValue) -> String {
        switch value {
        case .null: return "—"
        case .bool(let flag): return flag ? "Yes" : "No"
        case .int(let number): return String(number)
        case .double(let number): return String(format: "%.2f", number)
        case .string(let text): return text.isEmpty ? "—" : text
        case .array(let items): return items.count == 1 ? "1 item" : "\(items.count) items"
        case .object(let fields): return fields.count == 1 ? "1 field" : "\(fields.count) fields"
        }
    }

    /// `cpu_percent` becomes `Cpu percent`.
    public static func humanize(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard let first = words.first else { return key }
        return String(first).uppercased() + String(words.dropFirst())
    }

    private static func flatten(_ fields: [String: JSONValue], parent: String?, depth: Int) -> [ServerStatsRow] {
        var rows: [ServerStatsRow] = []
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            let name = humanize(key)
            let label = parent.map { "\($0) \(name.lowercased())" } ?? name
            if case .object(let nested) = value, depth > 0 {
                rows += flatten(nested, parent: label, depth: depth - 1)
            } else {
                rows.append(ServerStatsRow(label: label, value: text(value)))
            }
        }
        return rows
    }
}
