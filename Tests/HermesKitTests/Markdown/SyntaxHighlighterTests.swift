import Testing

@testable import HermesKit

struct SyntaxHighlighterTests {
    private func kinds(_ code: String, _ language: String?) -> [CodeToken.Kind] {
        SyntaxHighlighter.tokens(for: code, language: language).map(\.kind)
    }

    @Test func joiningTokensGivesBackTheCode() {
        let samples = [
            "let x = 42 // answer\nprint(\"hi \\\"there\\\"\")",
            "def f(a):\n    return a  # done",
            "/* open comment",
            "\"unterminated string",
            "",
        ]
        for code in samples {
            let joined = SyntaxHighlighter.tokens(for: code, language: nil).map(\.text).joined()
            #expect(joined == code)
        }
    }

    @Test func swiftKeywordsStringsCommentsAndNumbers() {
        let tokens = SyntaxHighlighter.tokens(for: "let n = 3 // c\nvar s = \"x\"", language: "swift")
        #expect(tokens.contains(CodeToken("let", .keyword)))
        #expect(tokens.contains(CodeToken("3", .number)))
        #expect(tokens.contains(CodeToken("// c", .comment)))
        #expect(tokens.contains(CodeToken("\"x\"", .string)))
    }

    @Test func pythonUsesHashComments() {
        #expect(kinds("# note", "python") == [.comment])
        #expect(kinds("x = 1 // 2", "python").contains(.number))
    }

    @Test func wordsContainingKeywordsStayPlain() {
        #expect(kinds("letter", "swift") == [.plain])
        #expect(kinds("x1", "swift") == [.plain])
    }
}
