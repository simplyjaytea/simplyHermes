import Foundation

/// Where dictated text goes in a draft: after what is already there, with one space between.
public enum DictationText {
    /// `draft` with `spoken` appended. Blank dictation leaves the draft as it is.
    public static func appending(_ spoken: String, to draft: String) -> String {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return draft }
        guard let last = draft.last, !last.isWhitespace else { return draft + text }
        return draft + " " + text
    }
}
