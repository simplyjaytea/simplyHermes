import Foundation

/// The level filter on the Logs screen. ``apiValue`` is the `level` query value. Logs carry names such as INFO
/// and WARNING. The spec types `level` as a string and lists no values, so the accepted values are unverified.
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
    /// How many lines to ask for.
    public var lines: Int

    /// Creates a filter. The default asks for 200 lines of the `agent` log.
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

/// Reads log lines out of a `GET /api/logs` answer. The recorder's `{file, lines}` answer has `lines` as a list of
/// strings (Fixtures/rest/GET_api_logs.json), kept in the server's order. A line's trailing newline is dropped. Any
/// other answer is shown as the JSON it is.
public enum ServerLogsRows {
    /// The lines to show, in the order the server sent them.
    public static func lines(from json: JSONValue) -> [String] {
        if case .object(let fields) = json, case .array(let items)? = fields["lines"] {
            return items.map(line)
        }
        return pretty(json).split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func line(_ item: JSONValue) -> String {
        if case .string(let text) = item { return text.trimmingCharacters(in: .newlines) }
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
        return String(bytes: data, encoding: .utf8) ?? "?"
    }
}
