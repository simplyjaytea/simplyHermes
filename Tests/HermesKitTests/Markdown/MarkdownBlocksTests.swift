import Testing

@testable import HermesKit

@Suite struct MarkdownBlocksTests {
    @Test func splitsParagraphsAndHeadings() {
        let blocks = MarkdownBlocks.parse("# Title\n\nFirst line\nsecond line\n\n## Next")
        #expect(
            blocks == [
                .heading(level: 1, text: "Title"), .paragraph("First line\nsecond line"),
                .heading(level: 2, text: "Next"),
            ])
    }

    @Test func fencedCodeKeepsIndentAndLanguage() {
        let blocks = MarkdownBlocks.parse("Run:\n```swift\nfunc a() {\n    print(1)\n}\n```\nDone")
        #expect(
            blocks == [
                .paragraph("Run:"), .code(language: "swift", text: "func a() {\n    print(1)\n}", isClosed: true),
                .paragraph("Done"),
            ])
    }

    @Test func unclosedFenceIsCodeWhileStreaming() {
        let blocks = MarkdownBlocks.parse("```bash\nls -la\nec")
        #expect(blocks == [.code(language: "bash", text: "ls -la\nec", isClosed: false)])
    }

    @Test func bulletAndNumberedLists() {
        let blocks = MarkdownBlocks.parse("- one\n- two\n\n3. three\n4. four")
        #expect(blocks == [.list(start: nil, items: ["one", "two"]), .list(start: 3, items: ["three", "four"])])
    }

    @Test func quotesAndRules() {
        let blocks = MarkdownBlocks.parse("> said\n> twice\n\n---\ntext")
        #expect(blocks == [.quote("said\ntwice"), .rule, .paragraph("text")])
    }

    @Test func plainTextIsOneParagraph() {
        #expect(MarkdownBlocks.parse("just words, 2 * 3 = 6") == [.paragraph("just words, 2 * 3 = 6")])
        #expect(MarkdownBlocks.parse("").isEmpty)
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
    }
}
