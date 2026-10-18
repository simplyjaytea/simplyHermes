import Foundation

/// What a composer token asks the server to complete.
public enum ComposerTrigger: Sendable, Equatable {
    /// A `/` that starts the message. `query` is the text after the slash.
    case slash(query: String)
    /// An `@` that starts a word. `query` is the text after the at sign.
    case mention(query: String)
}

/// A word the caret is in that the composer completes. The range counts UTF-16 units, the unit UIKit uses for text.
public struct ComposerToken: Sendable, Equatable {
    public var trigger: ComposerTrigger
    /// The whole word, from its `/` or `@` to the next space or the end of the text.
    public var range: Range<Int>
}

/// Finds completion tokens in composer text, and rewrites them when a completion is picked.
public enum ComposerTokens {
    private static let slash: UInt16 = 0x2F
    private static let atSign: UInt16 = 0x40

    /// The token the caret is in, or nil. A slash counts only as the first word of the message. An `@` counts at the
    /// start of any word, so an address such as `a@b.com` is not a mention.
    public static func active(in text: String, caret: Int) -> ComposerToken? {
        let units = Array(text.utf16)
        guard (0...units.count).contains(caret) else { return nil }
        var start = caret
        while start > 0, !isSpace(units[start - 1]) { start -= 1 }
        var end = caret
        while end < units.count, !isSpace(units[end]) { end += 1 }
        // The caret must sit after the trigger character, so the query can be read.
        guard start < caret else { return nil }
        let query = String(decoding: units[(start + 1)..<caret], as: UTF16.self)
        if units[start] == slash, start == 0 {
            return ComposerToken(trigger: .slash(query: query), range: start..<end)
        }
        if units[start] == atSign {
            return ComposerToken(trigger: .mention(query: query), range: start..<end)
        }
        return nil
    }

    /// Replaces the token with `replacement`, then a space unless a space already follows or the replacement ends a
    /// folder or a context prefix (`/` or `:`), where the next level is typed straight on. Returns the new text and
    /// the caret position after the replacement.
    public static func replacing(
        _ token: ComposerToken, in text: String, with replacement: String
    ) -> (text: String, caret: Int) {
        var units = Array(text.utf16)
        guard token.range.upperBound <= units.count else { return (text, units.count) }
        let followedBySpace = token.range.upperBound < units.count && isSpace(units[token.range.upperBound])
        let opensLevel = replacement.hasSuffix("/") || replacement.hasSuffix(":")
        let inserted = Array((followedBySpace || opensLevel ? replacement : replacement + " ").utf16)
        units.replaceSubrange(token.range, with: inserted)
        return (String(decoding: units, as: UTF16.self), token.range.lowerBound + inserted.count)
    }

    /// The mention words of the text, as UTF-16 ranges, so the composer can color them. A lone `@` is not a mention.
    public static func mentionRanges(in text: String) -> [Range<Int>] {
        let units = Array(text.utf16)
        var ranges: [Range<Int>] = []
        var index = 0
        while index < units.count {
            guard !isSpace(units[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < units.count, !isSpace(units[end]) { end += 1 }
            if units[index] == atSign, end - index > 1 {
                ranges.append(index..<end)
            }
            index = end
        }
        return ranges
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
