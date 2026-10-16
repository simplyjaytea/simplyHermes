import Foundation

/// Find in transcript (WP-30): which rows contain a query, in transcript order.
public enum TranscriptSearch {
    /// Ids of the rows whose text contains `query`, ignoring case and accents. An empty or blank query matches nothing.
    public static func matchingIDs(in items: [TranscriptItem], query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return items.compactMap { item in
            searchableText(of: item).range(of: needle, options: options) != nil ? item.id : nil
        }
    }

    /// The text of a row that find looks through: message text, reasoning, tool name, command and output.
    public static func searchableText(of item: TranscriptItem) -> String {
        switch item.content {
        case .user(let entry):
            return entry.text
        case .assistant(let entry):
            return [entry.text, entry.reasoning].compactMap { $0 }.joined(separator: "\n")
        case .tool(let entry):
            return [entry.name, entry.context, entry.resultText, entry.summary].compactMap { $0 }.joined(
                separator: "\n")
        case .other(_, let text):
            return text
        }
    }

    /// The match after `current` in `matches`, wrapping at the end. Nil when there are no matches.
    public static func next(after current: String?, in matches: [String]) -> String? {
        guard !matches.isEmpty else { return nil }
        guard let current, let index = matches.firstIndex(of: current) else { return matches[0] }
        return matches[(index + 1) % matches.count]
    }

    /// The match before `current` in `matches`, wrapping at the start. Nil when there are no matches.
    public static func previous(before current: String?, in matches: [String]) -> String? {
        guard !matches.isEmpty else { return nil }
        guard let current, let index = matches.firstIndex(of: current) else { return matches[matches.count - 1] }
        return matches[(index - 1 + matches.count) % matches.count]
    }
}
