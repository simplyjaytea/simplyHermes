import Foundation

/// Text copied from a terminal screen, ready for the chat composer.
public enum TerminalSnapshot {
    /// Formats screen lines as a code block, so the TUI's layout survives in the draft.
    ///
    /// Trailing spaces go, and blank lines go from both ends. Returns nil when nothing is left.
    public static func chatText(lines: [String]) -> String? {
        var body = lines.map(trimmingTrailingSpaces)
        while body.first == "" { body.removeFirst() }
        while body.last == "" { body.removeLast() }
        guard !body.isEmpty else { return nil }
        return "```\n" + body.joined(separator: "\n") + "\n```"
    }

    private static func trimmingTrailingSpaces(_ line: String) -> String {
        var result = Substring(line)
        while result.last == " " { result = result.dropLast() }
        return String(result)
    }
}
