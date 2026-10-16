/// A run of code text and what it is, for coloring.
public struct CodeToken: Sendable, Equatable {
    /// What a run of code is.
    public enum Kind: Sendable, Equatable {
        case plain
        case keyword
        case string
        case comment
        case number
    }

    public var text: String
    public var kind: Kind

    public init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// A small scanner that splits code into keywords, strings, comments and numbers. It is not a parser: it knows
/// a few language families by name, falls back to a generic C-like scan, and never fails on odd input. Joining the
/// token texts always gives back the original code.
public enum SyntaxHighlighter {
    private struct Rules {
        var keywords: Set<String>
        var lineComment: String?
        var blockComment: (open: String, close: String)?
    }

    /// Splits `code` into tokens for `language` (the info string after the opening fence, any case).
    public static func tokens(for code: String, language: String?) -> [CodeToken] {
        let rules = rules(for: language?.lowercased())
        let chars = Array(code)
        var result: [CodeToken] = []
        var plain = ""
        var index = 0

        func flushPlain() {
            if !plain.isEmpty { result.append(CodeToken(plain, .plain)) }
            plain = ""
        }
        func emit(_ text: String, _ kind: CodeToken.Kind) {
            flushPlain()
            result.append(CodeToken(text, kind))
        }
        func starts(_ marker: String, at position: Int) -> Bool {
            let marked = Array(marker)
            guard position + marked.count <= chars.count else { return false }
            return Array(chars[position..<position + marked.count]) == marked
        }

        while index < chars.count {
            let char = chars[index]
            if let line = rules.lineComment, starts(line, at: index) {
                var end = index
                while end < chars.count, chars[end] != "\n" { end += 1 }
                emit(String(chars[index..<end]), .comment)
                index = end
            } else if let block = rules.blockComment, starts(block.open, at: index) {
                var end = index + block.open.count
                while end < chars.count, !starts(block.close, at: end) { end += 1 }
                end = min(chars.count, end + block.close.count)
                emit(String(chars[index..<end]), .comment)
                index = end
            } else if char == "\"" || char == "'" || char == "`" {
                var end = index + 1
                while end < chars.count, chars[end] != char, chars[end] != "\n" || char == "`" {
                    end += chars[end] == "\\" ? 2 : 1
                }
                end = min(chars.count, end + 1)
                emit(String(chars[index..<end]), .string)
                index = end
            } else if char.isNumber, index == 0 || !isWordCharacter(chars[index - 1]) {
                var end = index
                while end < chars.count, chars[end].isNumber || chars[end] == "." || chars[end] == "_" { end += 1 }
                emit(String(chars[index..<end]), .number)
                index = end
            } else if isWordCharacter(char) {
                var end = index
                while end < chars.count, isWordCharacter(chars[end]) { end += 1 }
                let word = String(chars[index..<end])
                if rules.keywords.contains(word) { emit(word, .keyword) } else { plain += word }
                index = end
            } else {
                plain.append(char)
                index += 1
            }
        }
        flushPlain()
        return result
    }

    private static func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }

    private static func rules(for language: String?) -> Rules {
        switch language {
        case "python", "py":
            Rules(keywords: pythonWords, lineComment: "#", blockComment: nil)
        case "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "ruby", "rb":
            Rules(keywords: shellWords, lineComment: "#", blockComment: nil)
        case "sql":
            Rules(keywords: sqlWords, lineComment: "--", blockComment: ("/*", "*/"))
        case "json":
            Rules(keywords: ["true", "false", "null"], lineComment: nil, blockComment: nil)
        default:
            Rules(keywords: cLikeWords, lineComment: "//", blockComment: ("/*", "*/"))
        }
    }

    private static let cLikeWords: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "func",
        "function", "let", "var", "const", "class", "struct", "enum", "protocol", "extension", "import", "from",
        "export", "public", "private", "internal", "static", "final", "async", "await", "throws", "throw", "try",
        "catch", "guard", "in", "is", "as", "new", "null", "nil", "true", "false", "self", "this", "super", "fn",
        "pub", "mut", "impl", "trait", "use", "mod", "type", "interface", "package", "void", "int", "bool", "string",
    ]

    private static let pythonWords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "return", "import",
        "from", "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue", "lambda", "yield",
        "async", "await", "None", "True", "False", "self",
    ]

    private static let shellWords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "in", "echo",
        "export", "cd", "return", "true", "false", "null", "def", "end", "class", "module",
    ]

    private static let sqlWords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "drop",
        "alter", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "and",
        "or", "not", "null", "as", "distinct", "union", "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES",
        "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER",
        "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "AND", "OR", "NOT", "NULL", "AS", "DISTINCT", "UNION",
    ]
}
