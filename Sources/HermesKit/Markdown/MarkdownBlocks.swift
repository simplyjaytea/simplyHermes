/// One block of a chat message after block-level markdown is split out. Inline syntax (bold, links, code spans)
/// stays in the text and is rendered by the view.
public enum MarkdownBlock: Sendable, Equatable {
    /// A paragraph. Lines of one paragraph are joined with line breaks.
    case paragraph(String)
    /// A heading, level 1 to 6.
    case heading(level: Int, text: String)
    /// A fenced code block. `isClosed` is false while the closing fence is still streaming in.
    case code(language: String?, text: String, isClosed: Bool)
    /// A bulleted or numbered list. `start` is the first number of an ordered list, nil for bullets.
    case list(start: Int?, items: [String])
    /// A block quote.
    case quote(String)
    /// A horizontal rule.
    case rule
}

/// Splits chat text into blocks. It is forgiving about half-written input, so it can run on every streaming update.
public enum MarkdownBlocks {
    /// Parses `text` into blocks.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: (start: Int?, items: [String])?
        var quote: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushList() {
            if let list { blocks.append(.list(start: list.start, items: list.items)) }
            list = nil
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceInfo(trimmed) {
                flushAll()
                var body: [String] = []
                var closed = false
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                        closed = true
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: fence.language, text: body.joined(separator: "\n"), isClosed: closed))
            } else if trimmed.isEmpty {
                flushAll()
            } else if let heading = headingInfo(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .init(charactersIn: " ")))
            } else if let item = listItem(trimmed) {
                flushParagraph()
                flushQuote()
                if let current = list, (current.start == nil) == (item.number == nil) {
                    list?.items.append(item.text)
                } else {
                    flushList()
                    list = (item.number, [item.text])
                }
            } else {
                flushList()
                flushQuote()
                paragraph.append(trimmed)
            }
            index += 1
        }
        flushAll()
        return blocks
    }

    private static func fenceInfo(_ line: String) -> (marker: String, language: String?)? {
        for marker in ["```", "~~~"] where line.hasPrefix(marker) {
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return (marker, language.isEmpty ? nil : language.split(separator: " ").first.map(String.init))
        }
        return nil
    }

    private static func headingInfo(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> (number: Int?, text: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            return (nil, line.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")", rest.dropFirst().first == " " else { return nil }
        return (number, rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }
}
