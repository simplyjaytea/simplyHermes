import Foundation

/// One value of an answer that has no fixed shape, shown as a row: where it sits, and its text.
public struct SettingsAssistantRow: Identifiable, Sendable, Equatable {
    /// The key path, one component per key or array index. Unique within one answer.
    public var path: [String]
    /// The value as text: `true`, `false`, `null`, a number, a string, `[]` or `{}`.
    public var value: String
    /// True when a key on the path looks like it holds a secret. The UI masks these until the user taps.
    public var isSecret: Bool

    /// The path, as the row's identity.
    public var id: [String] { path }

    /// The path joined with dots, for display. Empty when the answer is a bare value.
    public var label: String { path.joined(separator: ".") }

    /// Creates a row.
    public init(path: [String], value: String, isSecret: Bool) {
        self.path = path
        self.value = value
        self.isSecret = isSecret
    }
}

/// Turns an answer into rows. The schema gives most answers of the assistant settings as any JSON, so the app shows
/// them without assuming key names.
public enum SettingsAssistantRows {
    /// Words that mark a key as a secret. Matching is by substring and ignores case, so `api_key`, `Token` and
    /// `db_password` all match. It errs toward masking: `max_tokens` is masked too, and one tap shows it.
    static let secretWords = [
        "key", "token", "secret", "password", "passwd", "credential", "cookie", "auth", "private",
    ]

    /// The rows of `answer`: object keys in sorted order, array items in order, and every value beneath a secret key
    /// marked secret. Empty containers show as `[]` or `{}`.
    public static func rows(for answer: JSONValue) -> [SettingsAssistantRow] {
        var rows: [SettingsAssistantRow] = []
        append(answer, path: [], secret: false, to: &rows)
        return rows
    }

    /// True when a key name looks like it holds a secret.
    public static func isSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return secretWords.contains { lowered.contains($0) }
    }

    private static func append(
        _ value: JSONValue, path: [String], secret: Bool, to rows: inout [SettingsAssistantRow]
    ) {
        switch value {
        case .object(let object) where !object.isEmpty:
            for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                append(child, path: path + [key], secret: secret || isSecretKey(key), to: &rows)
            }
        case .array(let items) where !items.isEmpty:
            for (index, item) in items.enumerated() {
                append(item, path: path + [String(index)], secret: secret, to: &rows)
            }
        default:
            rows.append(SettingsAssistantRow(path: path, value: text(of: value), isSecret: secret))
        }
    }

    private static func text(of value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .int(let number): String(number)
        case .double(let number): String(number)
        case .string(let string): string
        case .array: "[]"
        case .object: "{}"
        }
    }
}

/// The failures a settings screen meets before it reaches the server.
public enum SettingsAssistantFailure: Error, Sendable, Equatable {
    /// No server is chosen, or the chosen one is not connected.
    case noServer
}

/// The text a settings screen shows for an error. A server's own message passes through only when it sent one.
public enum SettingsAssistantErrorText {
    /// The message for `error`.
    public static func message(for error: any Error) -> String {
        switch error {
        case SettingsAssistantFailure.noServer: "Choose a server first."
        case is ConnectionUnavailable: "Connect to the server first."
        case RESTError.unauthorized: "Sign in to the server again."
        case RESTError.rateLimited: "The server is busy. Try again in a minute."
        case RESTError.http(404, _): "This server doesn't have this setting yet."
        case RESTError.http(_, let detail?): detail
        case RESTError.http(let status, nil): "The server answered with status \(status)."
        case RESTError.unexpectedContent: "The server sent a web page, not settings. Check the server address."
        case RESTError.decoding: "The server sent something the app doesn't understand."
        case RESTError.transport: "Couldn't reach the server."
        default: "Something went wrong. Try again."
        }
    }
}
