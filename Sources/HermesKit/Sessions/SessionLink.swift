import Foundation

/// A session in one profile: what an `@session:<profile>/<id>` link points at.
public struct SessionReference: Sendable, Hashable {
    /// The profile that owns the session, such as `default`.
    public var profile: String
    /// The stored session id, such as `20261014_032737_07e33f`.
    public var sessionID: String

    /// Creates a reference.
    public init(profile: String, sessionID: String) {
        self.profile = profile
        self.sessionID = sessionID
    }
}

/// The `@session:<profile>/<id>` link (WP-40): a reference to a session, which may belong to another profile.
///
/// The Hermes docs name this shape without defining its grammar, so this reads it strictly. The profile and the id are
/// each one or more ASCII letters, digits, `-` or `_`. A link starts at an `@` that does not follow a word character,
/// and it ends where the id ends. Code spans and fenced code blocks never hold links.
public enum SessionLink {
    /// The text before the profile.
    public static let marker = "@session:"

    /// A link found in text.
    public struct Match: Sendable, Equatable {
        /// The session the link names.
        public var reference: SessionReference
        /// Where the whole link sits in the text it was found in.
        public var range: Range<String.Index>
    }

    /// The link text for `reference`, or nil when a name holds a character the grammar does not allow.
    public static func format(_ reference: SessionReference) -> String? {
        guard isName(reference.profile), isName(reference.sessionID) else { return nil }
        return marker + reference.profile + "/" + reference.sessionID
    }

    /// The reference when `text` is exactly one link, ignoring surrounding whitespace. Nil for anything else.
    public static func parse(_ text: String) -> SessionReference? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = matches(in: trimmed).first, match.range == trimmed.startIndex..<trimmed.endIndex else {
            return nil
        }
        return match.reference
    }

    /// Every link in `text`, in order. Code spans and fenced code blocks are skipped.
    public static func matches(in text: String) -> [Match] {
        var found: [Match] = []
        for region in proseRegions(of: text) {
            scan(region, in: text, into: &found)
        }
        return found
    }

    /// `text` with each link replaced by a Markdown link to its session URL, so the Markdown renderer shows it as a
    /// tappable link. Everything else, code included, is left as written.
    public static func linkified(_ text: String) -> String {
        let found = matches(in: text)
        guard !found.isEmpty else { return text }
        var result = ""
        var cursor = text.startIndex
        for match in found {
            result += text[cursor..<match.range.lowerBound]
            let url = HermesURL.session(match.reference).absoluteString
            result += "[\(text[match.range])](\(url))"
            cursor = match.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Whether `value` is a non-empty profile or session id: ASCII letters, digits, `-` and `_` only.
    static func isName(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(isNameCharacter)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
    }

    // MARK: - Finding links

    /// The parts of `text` outside code: fenced blocks and code spans are left out.
    private static func proseRegions(of text: String) -> [Range<String.Index>] {
        var regions: [Range<String.Index>] = []
        var cursor = text.startIndex
        for block in fencedBlocks(in: text) {
            regions += outsideCodeSpans(cursor..<block.lowerBound, in: text)
            cursor = block.upperBound
        }
        regions += outsideCodeSpans(cursor..<text.endIndex, in: text)
        return regions
    }

    private static func outsideCodeSpans(_ region: Range<String.Index>, in text: String) -> [Range<String.Index>] {
        var parts: [Range<String.Index>] = []
        var cursor = region.lowerBound
        for span in codeSpans(in: region, of: text) {
            if cursor < span.lowerBound { parts.append(cursor..<span.lowerBound) }
            cursor = span.upperBound
        }
        if cursor < region.upperBound { parts.append(cursor..<region.upperBound) }
        return parts
    }

    /// A fence line, as far as the closing rule needs it.
    private struct Fence {
        let marker: Character
        let length: Int
        /// True when only spaces follow the run, which a closing fence needs.
        let isBare: Bool
    }

    /// Fenced code blocks: from the opening fence line through the closing fence, or to the end when it never closes.
    private static func fencedBlocks(in text: String) -> [Range<String.Index>] {
        var blocks: [Range<String.Index>] = []
        var open: (fence: Fence, start: String.Index)?
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            if let fence = fenceMarker(in: text[lineStart..<lineEnd]) {
                if let current = open {
                    if fence.marker == current.fence.marker, fence.length >= current.fence.length, fence.isBare {
                        blocks.append(current.start..<next)
                        open = nil
                    }
                } else {
                    open = (fence, lineStart)
                }
            }
            lineStart = next
        }
        if let open { blocks.append(open.start..<text.endIndex) }
        return blocks
    }

    /// A fence line: up to three spaces, then three or more backticks or tildes.
    private static func fenceMarker(in line: Substring) -> Fence? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let run = rest.prefix { $0 == marker }
        guard run.count >= 3 else { return nil }
        let trailing = rest.dropFirst(run.count)
        let isBare = trailing.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
        return Fence(marker: marker, length: run.count, isBare: isBare)
    }

    /// Code spans inside `region`: a run of backticks through the next run of the same length. An unmatched run is text.
    private static func codeSpans(in region: Range<String.Index>, of text: String) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var index = region.lowerBound
        while index < region.upperBound {
            guard text[index] == "`" else {
                index = text.index(after: index)
                continue
            }
            let runEnd = endOfRun(of: "`", from: index, limit: region.upperBound, in: text)
            let length = text.distance(from: index, to: runEnd)
            var probe = runEnd
            var closing: Range<String.Index>?
            while probe < region.upperBound {
                guard text[probe] == "`" else {
                    probe = text.index(after: probe)
                    continue
                }
                let closeEnd = endOfRun(of: "`", from: probe, limit: region.upperBound, in: text)
                if text.distance(from: probe, to: closeEnd) == length {
                    closing = index..<closeEnd
                    break
                }
                probe = closeEnd
            }
            if let closing {
                spans.append(closing)
                index = closing.upperBound
            } else {
                index = runEnd
            }
        }
        return spans
    }

    private static func endOfRun(
        of character: Character, from start: String.Index, limit: String.Index, in text: String
    ) -> String.Index {
        var index = start
        while index < limit, text[index] == character {
            index = text.index(after: index)
        }
        return index
    }

    private static func scan(_ region: Range<String.Index>, in text: String, into found: inout [Match]) {
        var index = region.lowerBound
        while index < region.upperBound {
            if let link = linkStarting(at: index, limit: region.upperBound, in: text) {
                found.append(link)
                index = link.range.upperBound
            } else {
                index = text.index(after: index)
            }
        }
    }

    /// The link that starts at `index`, if there is one that ends before `limit`.
    private static func linkStarting(at index: String.Index, limit: String.Index, in text: String) -> Match? {
        guard text[index] == "@", canStart(at: index, in: text) else { return nil }
        return match(at: index, limit: limit, in: text)
    }

    /// An `@` starts a link unless it follows a letter, a digit, or one of `_-/@.\[]` and a backtick.
    private static func canStart(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let before = text[text.index(before: index)]
        return !(before.isLetter || before.isNumber || "_-/@.\\[]`".contains(before))
    }

    /// The link that starts at `start`, if its profile, `/` and id all lie before `limit`.
    private static func match(at start: String.Index, limit: String.Index, in text: String) -> Match? {
        guard let markerEnd = text.index(start, offsetBy: marker.count, limitedBy: limit),
            text[start..<markerEnd] == marker
        else { return nil }
        let profileEnd = endOfName(from: markerEnd, limit: limit, in: text)
        guard profileEnd > markerEnd, profileEnd < limit, text[profileEnd] == "/" else { return nil }
        let idStart = text.index(after: profileEnd)
        let idEnd = endOfName(from: idStart, limit: limit, in: text)
        guard idEnd > idStart else { return nil }
        // "ops/abc/x" is a path, and "abc.def" is a longer word, not a sentence that ends after "abc".
        if idEnd < text.endIndex, text[idEnd] == "/" { return nil }
        if idEnd < text.endIndex, text[idEnd] == ".", isNameCharacter(after: idEnd, in: text) { return nil }
        let reference = SessionReference(
            profile: String(text[markerEnd..<profileEnd]), sessionID: String(text[idStart..<idEnd]))
        return Match(reference: reference, range: start..<idEnd)
    }

    /// Whether the character after `index` is a name character.
    private static func isNameCharacter(after index: String.Index, in text: String) -> Bool {
        let next = text.index(after: index)
        return next < text.endIndex && isNameCharacter(text[next])
    }

    private static func endOfName(from start: String.Index, limit: String.Index, in text: String) -> String.Index {
        var index = start
        while index < limit, isNameCharacter(text[index]) {
            index = text.index(after: index)
        }
        return index
    }
}
