import HermesKit
import Testing

@Suite struct MessageQuoteTests {
    @Test func shortTextIsQuotedWhole() {
        #expect(MessageQuote.block(for: "Disk is full") == "> Disk is full\n\n")
    }

    @Test func everyLineIsQuotedAndBlankLinesStayInTheQuote() {
        let text = "First line\n\nThird line"
        #expect(MessageQuote.block(for: text) == "> First line\n>\n> Third line\n\n")
    }

    @Test func longTextIsCutAtTheLimitWithAnEllipsis() {
        let text = String(repeating: "a", count: 1000)
        let quote = MessageQuote.block(for: text)
        #expect(quote == "> " + String(repeating: "a", count: 280) + "…\n\n")
    }

    @Test func textAtExactlyTheLimitHasNoEllipsis() {
        let text = String(repeating: "b", count: 280)
        #expect(!MessageQuote.block(for: text).contains("…"))
    }

    @Test func surroundingWhitespaceIsDropped() {
        #expect(MessageQuote.block(for: "\n\n  hello  \n") == "> hello\n\n")
    }

    @Test func emptyTextGivesNoQuote() {
        #expect(MessageQuote.block(for: "  \n ").isEmpty)
        #expect(MessageQuote.inserting("   ", into: "draft") == "draft")
    }

    @Test func existingDraftIsKeptAfterTheQuote() {
        let result = MessageQuote.inserting("Use du -sh", into: "And for logs?")
        #expect(result == "> Use du -sh\n\nAnd for logs?")
    }

    @Test func emptyDraftGetsJustTheQuote() {
        #expect(MessageQuote.inserting("Hi", into: "") == "> Hi\n\n")
    }

    @Test func leadingNewlinesOfTheDraftAreNotDoubled() {
        #expect(MessageQuote.inserting("Hi", into: "\n\nnext") == "> Hi\n\nnext")
    }

    @Test func quotingKeepsUnicodeCharactersWhole() {
        let text = String(repeating: "👍🏽", count: 300)
        let quote = MessageQuote.block(for: text)
        #expect(quote.hasPrefix("> 👍🏽"))
        #expect(quote.hasSuffix("…\n\n"))
    }
}
