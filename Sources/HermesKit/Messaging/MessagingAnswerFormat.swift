import Foundation

/// Shows an answer the server sent without a schema, as readable JSON. A value under a key that looks like a secret
/// (a token, password or key) is replaced with a mask, so secrets never appear on screen.
public enum MessagingAnswerFormat {
    /// The answer as indented JSON with sorted keys and unescaped slashes, with secrets masked. Empty when it cannot
    /// be encoded.
    public static func displayText(_ answer: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(masked(answer, underSecretKey: false)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Words that mark a key as secret. Matching ignores case. Everything under such a key is masked.
    private static let secretWords = [
        "token", "secret", "password", "passwd", "key", "credential", "cookie", "authorization", "oauth",
    ]

    private static let mask = "••••"

    private static func isSecretKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return secretWords.contains { lowered.contains($0) }
    }

    private static func masked(_ value: JSONValue, underSecretKey: Bool) -> JSONValue {
        switch value {
        case .object(let members):
            var result: [String: JSONValue] = [:]
            for (key, member) in members {
                result[key] = masked(member, underSecretKey: underSecretKey || isSecretKey(key))
            }
            return .object(result)
        case .array(let items):
            return .array(items.map { masked($0, underSecretKey: underSecretKey) })
        case .null:
            return .null
        default:
            return underSecretKey ? .string(mask) : value
        }
    }
}
