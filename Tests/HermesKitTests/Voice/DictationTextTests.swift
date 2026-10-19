import Testing

@testable import HermesKit

@Suite struct DictationTextTests {
    @Test func dictationFillsAnEmptyDraft() {
        #expect(DictationText.appending("hello there", to: "") == "hello there")
    }

    @Test func dictationGoesAfterWordsWithOneSpace() {
        #expect(DictationText.appending("and more", to: "first") == "first and more")
    }

    @Test func noExtraSpaceAfterWhitespaceOrNewline() {
        #expect(DictationText.appending("more", to: "first ") == "first more")
        #expect(DictationText.appending("more", to: "first\n") == "first\nmore")
    }

    @Test func blankDictationKeepsTheDraft() {
        #expect(DictationText.appending("  \n", to: "keep me") == "keep me")
    }
}
