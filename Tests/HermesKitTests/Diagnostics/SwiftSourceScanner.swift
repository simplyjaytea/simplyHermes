import Foundation

/// Reads Swift source the way the network guards need: comments are gone, and string literals are either blanked or kept,
/// with the code inside `\( )` interpolation always kept. It follows the real lexical rules the guards depend on:
/// `//` and nested `/* */` comments, plain, raw (`#"..."#`) and multi-line (`"""`) strings, and interpolation that
/// contains strings of its own. A `//` inside a string is text, not a comment, and a brace in a string or comment is not
/// a brace. Line numbers are kept: line N of the result is line N of the source.
enum SwiftSourceScanner {
    /// The code of each line of `text`.
    /// - Parameter keepStrings: keep what is inside string literals (so a name in a string still counts). When false,
    ///   a string reads as `""`, so a brace or a name in plain text is not seen.
    static func codeLines(_ text: String, keepStrings: Bool) -> [String] {
        var lexer = SourceLexer(text: text, keepStrings: keepStrings)
        return lexer.run()
    }
}

private enum LexerMode {
    /// Code. `parens` counts the open parentheses of an interpolation; nil at the top level.
    case code(parens: Int?)
    case string(hashes: Int, multiline: Bool)
}

private struct SourceLexer {
    let scalars: [Unicode.Scalar]
    let keepStrings: Bool
    var lines: [String] = []
    var line = String.UnicodeScalarView()
    var stack: [LexerMode] = [.code(parens: nil)]
    var blockDepth = 0
    var inLineComment = false
    var index = 0

    init(text: String, keepStrings: Bool) {
        scalars = Array(text.unicodeScalars)
        self.keepStrings = keepStrings
    }

    private func scalar(_ position: Int) -> Unicode.Scalar? { position < scalars.count ? scalars[position] : nil }

    private func hashes(from start: Int) -> Int {
        var count = 0
        while scalar(start + count) == "#" { count += 1 }
        return count
    }

    mutating func run() -> [String] {
        while index < scalars.count { step() }
        lines.append(String(line))
        return lines
    }

    private mutating func step() {
        let current = scalars[index]
        if current == "\n" {
            endLine()
        } else if inLineComment {
            index += 1
        } else if blockDepth > 0 {
            skipBlockComment(current)
        } else if case .string(let open, let multiline) = stack[stack.count - 1] {
            readString(current, open: open, multiline: multiline)
        } else if case .code(let parens) = stack[stack.count - 1] {
            readCode(current, parens: parens)
        }
    }

    private mutating func endLine() {
        lines.append(String(line))
        line = String.UnicodeScalarView()
        inLineComment = false
        // A plain string that was never closed ends with its line.
        if case .string(_, false)? = stack.last { stack.removeLast() }
        index += 1
    }

    private mutating func skipBlockComment(_ current: Unicode.Scalar) {
        if current == "*", scalar(index + 1) == "/" {
            blockDepth -= 1
            index += 2
        } else if current == "/", scalar(index + 1) == "*" {
            blockDepth += 1
            index += 2
        } else {
            index += 1
        }
    }

    // MARK: Strings

    private mutating func readString(_ current: Unicode.Scalar, open: Int, multiline: Bool) {
        if current == "\\" {
            readEscape(open: open)
        } else if current == "\"", closesString(open: open, multiline: multiline) {
            stack.removeLast()
            if keepStrings { line.append("\"") }
            index += (multiline ? 3 : 1) + open
        } else {
            keep(current)
            index += 1
        }
    }

    private mutating func keep(_ scalar: Unicode.Scalar) {
        if keepStrings { line.append(scalar) }
    }

    private func closesString(open: Int, multiline: Bool) -> Bool {
        guard multiline else { return hashes(from: index + 1) >= open }
        return scalar(index + 1) == "\"" && scalar(index + 2) == "\"" && hashes(from: index + 3) >= open
    }

    /// A backslash inside a string: the start of an interpolation, another escape, or (in a raw string) plain text.
    private mutating func readEscape(open: Int) {
        let run = hashes(from: index + 1)
        if run == open, scalar(index + 1 + open) == "(" {
            stack.append(.code(parens: 0))
            line.append(" ")
            index += 2 + open
        } else if run == open {
            if keepStrings { line.append(contentsOf: scalars[index...min(index + 1 + open, scalars.count - 1)]) }
            index += 2 + open
        } else {
            keep("\\")
            index += 1
        }
    }

    // MARK: Code

    private mutating func readCode(_ current: Unicode.Scalar, parens: Int?) {
        if current == "/", scalar(index + 1) == "/" {
            inLineComment = true
            index += 2
        } else if current == "/", scalar(index + 1) == "*" {
            blockDepth = 1
            index += 2
        } else if startsString(current) {
            beginString()
        } else if let parens, current == "(" || current == ")" {
            trackParen(current, parens: parens)
        } else {
            line.append(current)
            index += 1
        }
    }

    private func startsString(_ current: Unicode.Scalar) -> Bool {
        (current == "\"" || current == "#") && scalar(index + hashes(from: index)) == "\""
    }

    private mutating func beginString() {
        let open = hashes(from: index)
        let quote = index + open
        let multiline = scalar(quote + 1) == "\"" && scalar(quote + 2) == "\""
        stack.append(.string(hashes: open, multiline: multiline))
        line.append(contentsOf: (keepStrings ? "\"" : "\"\"").unicodeScalars)
        index = quote + (multiline ? 3 : 1)
    }

    /// A parenthesis inside an interpolation. The one that closes the interpolation returns to the string.
    private mutating func trackParen(_ current: Unicode.Scalar, parens: Int) {
        index += 1
        if current == "(" {
            stack[stack.count - 1] = .code(parens: parens + 1)
            line.append(current)
        } else if parens == 0 {
            stack.removeLast()
            line.append(" ")
        } else {
            stack[stack.count - 1] = .code(parens: parens - 1)
            line.append(current)
        }
    }
}
