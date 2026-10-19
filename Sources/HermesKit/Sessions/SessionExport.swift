import Foundation

/// Why a session could not be exported.
public enum SessionExportError: Error, Sendable, Equatable {
    /// The server's answer does not parse as JSON, for example a login page sent with a success status.
    case notJSON
}

/// Naming and checks for a session saved as a file (WP-40).
public enum SessionExport {
    /// `hermes-session-<title>.json`. The title is reduced to characters that are safe in a file name. When it leaves
    /// nothing, the session id is used instead.
    public static func fileName(title: String?, sessionID: String) -> String {
        let fromTitle = fileSafe(title ?? "")
        let stem = fromTitle.isEmpty ? fileSafe(sessionID) : fromTitle
        return "hermes-session-" + (stem.isEmpty ? "chat" : stem) + ".json"
    }

    /// Whether `data` parses as JSON. The export has no response schema, so this is the only check made on it.
    public static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// Keeps letters, digits, `-` and `_`. Whitespace becomes one `-`, and everything else is dropped. At most 60
    /// characters.
    static func fileSafe(_ text: String) -> String {
        var kept = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                kept.append(character)
            } else if character.isWhitespace, kept.last != "-" {
                kept.append("-")
            }
        }
        let trimmed = kept.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return String(trimmed.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }
}
