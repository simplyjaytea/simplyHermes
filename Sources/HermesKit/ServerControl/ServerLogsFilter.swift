import Foundation

/// The level filter on the Logs screen. ``apiValue`` is the `level` query value (Python logging names).
public enum ServerLogsLevel: String, Sendable, Equatable, CaseIterable, Identifiable {
    case all
    case error
    case warning
    case info
    case debug

    /// Identity for pickers.
    public var id: String { rawValue }

    /// Name to show.
    public var title: String {
        switch self {
        case .all: return "All levels"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    /// The `level` query value, or nil for no level filter.
    public var apiValue: String? {
        switch self {
        case .all: return nil
        case .error: return "ERROR"
        case .warning: return "WARNING"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        }
    }
}

/// The query for `GET /api/logs`. Empty text fields are left out, so the server's defaults apply.
public struct ServerLogsFilter: Sendable, Equatable {
    /// Log file name. The server reads `agent` when none is given.
    public var file: String
    /// Level filter.
    public var level: ServerLogsLevel
    /// Text to search for.
    public var search: String
    /// How many lines to return.
    public var lines: Int

    /// Creates a filter. The default reads the last 200 lines of the `agent` log.
    public init(file: String = "agent", level: ServerLogsLevel = .all, search: String = "", lines: Int = 200) {
        self.file = file
        self.level = level
        self.search = search
        self.lines = lines
    }

    /// The query items for the non-empty fields.
    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        let fileName = file.trimmingCharacters(in: .whitespaces)
        if !fileName.isEmpty { items.append(URLQueryItem(name: "file", value: fileName)) }
        items.append(URLQueryItem(name: "lines", value: String(lines)))
        if let apiLevel = level.apiValue { items.append(URLQueryItem(name: "level", value: apiLevel)) }
        let text = search.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { items.append(URLQueryItem(name: "search", value: text)) }
        return items
    }
}

/// Reads log lines out of a `GET /api/logs` answer. The OpenAPI leaves the answer untyped, so this takes the
/// first array of lines it finds and shows anything else as the JSON it is.
public enum ServerLogsRows {
    /// Keys that may hold the list of lines, in order of preference.
    static let listKeys = ["lines", "entries", "logs", "records", "items"]

    /// The lines to show, in the order the server sent them.
    public static func lines(from json: JSONValue) -> [String] {
        switch json {
        case .array(let items):
            return items.map(line)
        case .string(let text):
            return text.split(whereSeparator: \.isNewline).map(String.init)
        case .object(let fields):
            for key in listKeys {
                if case .array(let items)? = fields[key] { return items.map(line) }
            }
            return pretty(json).split(whereSeparator: \.isNewline).map(String.init)
        default:
            return [ServerStatsRows.text(json)]
        }
    }

    private static func line(_ item: JSONValue) -> String {
        if case .string(let text) = item { return text }
        return compact(item)
    }

    private static func compact(_ json: JSONValue) -> String {
        encoded(json, formatting: [.sortedKeys])
    }

    private static func pretty(_ json: JSONValue) -> String {
        encoded(json, formatting: [.sortedKeys, .prettyPrinted])
    }

    private static func encoded(_ json: JSONValue, formatting: JSONEncoder.OutputFormatting) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        guard let data = try? encoder.encode(json) else { return "?" }
        return String(decoding: data, as: UTF8.self)
    }
}
