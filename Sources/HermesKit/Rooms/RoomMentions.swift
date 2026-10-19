import Foundation

/// What routing does with a `@token` in a room message (WP-43 spec, sections 2 and 7).
public enum RoomMentionKind: Sendable, Equatable {
    /// `@user`: the room waits on a person.
    case human
    /// `@all` or `@everyone`: every member.
    case everyone
    /// A member's handle, lower-cased.
    case member(String)
}

/// A mention routing honors, from its `@` through the end of its token.
public struct RoomMentionSpan: Sendable, Equatable {
    /// From the `@` to the end of the token.
    public let range: Range<String.Index>
    /// What the mention routes to.
    public let kind: RoomMentionKind
}

/// The `@` the composer is completing, and the characters typed after it.
public struct RoomCompletion: Sendable, Equatable {
    /// From the `@` to the caret.
    public let range: Range<String.Index>
    /// The typed characters after the `@`, lower-cased.
    public let query: String
}

/// Mention styling, the composer picker, and the slash-command guard for rooms (WP-43 spec, sections 2 and 7).
public enum RoomMentions {
    /// The broadcast handles, offered first by the picker.
    public static let broadcastHandles = ["everyone", "all"]

    /// The mentions routing honors. A token that names nobody stays plain, as the server ignores it.
    public static func spans(in text: String, handles: [String]) -> [RoomMentionSpan] {
        let known = Set(handles.map { $0.lowercased() })
        var spans: [RoomMentionSpan] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "@" else {
                index = text.index(after: index)
                continue
            }
            let tokenStart = text.index(after: index)
            let tokenEnd = endOfToken(in: text, from: tokenStart)
            let token = String(text[tokenStart..<tokenEnd]).lowercased()
            if !token.isEmpty, let kind = routedKind(of: token, known: known) {
                spans.append(RoomMentionSpan(range: index..<tokenEnd, kind: kind))
            }
            index = tokenEnd
        }
        return spans
    }

    /// True when a message mentions `@user` as a word, which badges the room for the person (WP-43 spec, section 7).
    public static func asksUser(_ text: String) -> Bool {
        let lowered = text.lowercased()
        var search = lowered.startIndex
        while let atSign = lowered[search...].firstIndex(of: "@") {
            let afterAt = lowered.index(after: atSign)
            if lowered[afterAt...].hasPrefix("user") {
                let end = lowered.index(afterAt, offsetBy: 4)
                if end == lowered.endIndex || !isWordCharacter(lowered[end]) {
                    return true
                }
            }
            search = afterAt
        }
        return false
    }

    /// The completion under the caret: the text before it ends in `@` at a word start, and the characters typed after
    /// that `@` are handle characters.
    public static func completion(in text: String, caret: String.Index) -> RoomCompletion? {
        var start = caret
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character == "@" {
                let atWordStart = previous == text.startIndex || text[text.index(before: previous)].isWhitespace
                guard atWordStart else { return nil }
                let query = String(text[text.index(after: previous)..<caret]).lowercased()
                return RoomCompletion(range: previous..<caret, query: query)
            }
            guard isPickerCharacter(character) else { return nil }
            start = previous
        }
        return nil
    }

    /// What the picker offers for a completion: the broadcast handles, then the members, filtered by the typed prefix.
    public static func options(for completion: RoomCompletion, handles: [String]) -> [String] {
        (broadcastHandles + handles).filter { $0.lowercased().hasPrefix(completion.query) }
    }

    /// The text with the completion replaced by `@handle `, with the trailing space the server's routing expects.
    public static func inserting(_ handle: String, into text: String, replacing completion: RoomCompletion) -> String {
        var result = text
        result.replaceSubrange(completion.range, with: "@\(handle) ")
        return result
    }

    /// True for `/command` text, which a group room refuses (WP-43 spec, section 2).
    public static func isSlashCommand(_ text: String) -> Bool {
        guard text.first == "/" else { return false }
        var index = text.index(after: text.startIndex)
        guard index < text.endIndex, isLowercaseLetter(text[index]) else { return false }
        index = text.index(after: index)
        while index < text.endIndex, isCommandCharacter(text[index]) {
            index = text.index(after: index)
        }
        return index == text.endIndex || text[index].isWhitespace
    }

    private static func routedKind(of token: String, known: Set<String>) -> RoomMentionKind? {
        if token == "user" { return .human }
        if broadcastHandles.contains(token) { return .everyone }
        return known.contains(token) ? .member(token) : nil
    }

    /// The end of the token that starts at `start`. The token is `[A-Za-z0-9][A-Za-z0-9._:-]*`, as the server reads it.
    private static func endOfToken(in text: String, from start: String.Index) -> String.Index {
        guard start < text.endIndex, isTokenStart(text[start]) else { return start }
        var end = start
        while end < text.endIndex, isTokenCharacter(text[end]) {
            end = text.index(after: end)
        }
        return end
    }

    private static func isTokenStart(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        isTokenStart(character) || "._:-".contains(character)
    }

    private static func isPickerCharacter(_ character: Character) -> Bool {
        isTokenStart(character) || "._-".contains(character)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || isTokenStart(character)
    }

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLowercase && character.isLetter
    }

    private static func isCommandCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}
