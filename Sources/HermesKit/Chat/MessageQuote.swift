import Foundation

/// Builds the Markdown quote that "Quote in reply" puts at the start of a draft. The quote is the user's own edit of
/// the draft: nothing is sent until they press Send.
public enum MessageQuote {
    /// Characters of the message that go into the quote. Longer messages are cut and end with "…".
    public static let defaultLimit = 280

    /// `text` as a Markdown block quote: every line starts with "> ", and the block ends with an empty line so the
    /// reply starts on its own paragraph. Leading and trailing blank lines are dropped. Empty text gives "".
    public static func block(for text: String, limit: Int = defaultLimit) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return "" }
        var excerpt = String(trimmed.prefix(limit))
        if trimmed.count > limit {
            excerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        let lines = excerpt.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
        return lines.joined(separator: "\n") + "\n\n"
    }

    /// The draft with the quote of `text` put in front. What the user had typed is kept after the quote.
    public static func inserting(_ text: String, into draft: String, limit: Int = defaultLimit) -> String {
        let quote = block(for: text, limit: limit)
        guard !quote.isEmpty else { return draft }
        let rest = draft.drop { $0.isNewline }
        return quote + rest
    }
}
