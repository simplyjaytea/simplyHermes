import Foundation
import Testing

@testable import HermesKit

@Suite struct ComposerTokensTests {
    @Test func slashAtTheStartIsAToken() throws {
        let token = try #require(ComposerTokens.active(in: "/he", caret: 3))
        #expect(token.trigger == .slash(query: "he"))
        #expect(token.range == 0..<3)
    }

    @Test func slashEndsAtTheFirstSpace() throws {
        let token = try #require(ComposerTokens.active(in: "/help me", caret: 5))
        #expect(token.trigger == .slash(query: "help"))
        #expect(ComposerTokens.active(in: "/help me", caret: 8) == nil)
    }

    @Test func slashLaterInTheMessageIsNotAToken() {
        #expect(ComposerTokens.active(in: "look /he", caret: 8) == nil)
    }

    @Test func atSignStartsAMentionAtAnyWord() throws {
        let token = try #require(ComposerTokens.active(in: "see @src/ma", caret: 11))
        #expect(token.trigger == .mention(query: "src/ma"))
        #expect(token.range == 4..<11)
    }

    @Test func atSignInsideAWordIsNotAMention() {
        #expect(ComposerTokens.active(in: "mail me at a@b.com", caret: 18) == nil)
    }

    @Test func caretBeforeTheTriggerIsNotInsideTheToken() {
        #expect(ComposerTokens.active(in: "/he", caret: 0) == nil)
    }

    @Test func replacingTheSlashTokenAddsASpace() throws {
        let token = try #require(ComposerTokens.active(in: "/he", caret: 3))
        let result = ComposerTokens.replacing(token, in: "/he", with: "/help")
        #expect(result.text == "/help ")
        #expect(result.caret == 6)
    }

    @Test func replacingAMentionKeepsTheSpaceThatFollowsIt() throws {
        let text = "see @src/ma now"
        let token = try #require(ComposerTokens.active(in: text, caret: 11))
        let result = ComposerTokens.replacing(token, in: text, with: "@src/main.swift")
        #expect(result.text == "see @src/main.swift now")
        #expect(result.caret == 19)
    }

    @Test func mentionRangesFindAtWordsOnly() {
        #expect(ComposerTokens.mentionRanges(in: "see @a.txt and @ or x@y") == [4..<10])
    }

    @Test func completionItemsDecodeWithOptionalFields() throws {
        let object: JSONValue = [
            "items": [["text": "/help", "meta": "Show help", "kind": "command"], ["text": "/new"]]
        ]
        let result = try object.decode(CompleteSlashResult.self)
        #expect(result.items.map(\.text) == ["/help", "/new"])
        #expect(result.items[0].kind == "command")
        #expect(result.items[1].label == "/new")
        let empty = try JSONValue.object([:]).decode(CompletionItemsResult.self)
        #expect(empty.items.isEmpty)
    }
}
