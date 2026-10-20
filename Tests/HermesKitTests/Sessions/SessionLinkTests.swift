import Foundation
import HermesKit
import Testing

@Suite struct SessionLinkTests {
    private let reference = SessionReference(profile: "ops", sessionID: "20261014_032737_07e33f")

    @Test func formatsAndParsesTheSameReference() throws {
        let text = try #require(SessionLink.format(reference))
        #expect(text == "@session:ops/20261014_032737_07e33f")
        #expect(SessionLink.parse(text) == reference)
    }

    @Test func formatRefusesNamesOutsideTheGrammar() {
        #expect(SessionLink.format(SessionReference(profile: "my profile", sessionID: "a")) == nil)
        #expect(SessionLink.format(SessionReference(profile: "ops", sessionID: "a/b")) == nil)
        #expect(SessionLink.format(SessionReference(profile: "", sessionID: "a")) == nil)
        #expect(SessionLink.format(SessionReference(profile: "ops", sessionID: "café")) == nil)
    }

    @Test func parseTakesExactlyOneLinkIgnoringOuterWhitespace() {
        #expect(SessionLink.parse("  @session:ops/abc \n") == SessionReference(profile: "ops", sessionID: "abc"))
        #expect(SessionLink.parse("see @session:ops/abc") == nil)
        #expect(SessionLink.parse("@session:ops/abc.") == nil, "the period is outside the link")
        #expect(SessionLink.parse(#"@session:"Weekly review""#) == nil, "title forms are not links")
    }

    @Test func findsEveryLinkInProse() {
        let text = "Compare @session:ops/abc with (@session:default/def1), then @session:ops/xyz_9."
        let found = SessionLink.matches(in: text)
        #expect(
            found.map(\.reference) == [
                SessionReference(profile: "ops", sessionID: "abc"),
                SessionReference(profile: "default", sessionID: "def1"),
                SessionReference(profile: "ops", sessionID: "xyz_9"),
            ])
        #expect(
            found.map { String(text[$0.range]) } == ["@session:ops/abc", "@session:default/def1", "@session:ops/xyz_9"])
    }

    @Test func aLinkNeedsAWordBoundaryAndWholeNames() {
        #expect(SessionLink.matches(in: "mail me@session:ops/abc").isEmpty)
        #expect(SessionLink.matches(in: "@session:ops").isEmpty, "no id")
        #expect(SessionLink.matches(in: "@session:/abc").isEmpty, "no profile")
        #expect(SessionLink.matches(in: "@session:ops/abc.def").isEmpty, "a longer word")
        #expect(SessionLink.matches(in: "@session:ops/abc/extra").isEmpty, "a path")
        #expect(SessionLink.matches(in: "@session:ops/abc, ok").map(\.reference.sessionID) == ["abc"])
    }

    @Test func codeIsNeverALink() {
        #expect(SessionLink.matches(in: "Use `@session:ops/abc` here").isEmpty)
        #expect(SessionLink.matches(in: "``a `@session:ops/abc` b``").isEmpty)
        #expect(SessionLink.matches(in: "```\n@session:ops/abc\n```\n").isEmpty)
        #expect(SessionLink.matches(in: "~~~swift\n@session:ops/abc\n~~~").isEmpty)
        let after = SessionLink.matches(in: "```\n@session:ops/abc\n```\nthen @session:ops/def")
        #expect(after.map(\.reference.sessionID) == ["def"])
    }

    @Test func anUnmatchedBacktickIsText() {
        #expect(SessionLink.matches(in: "a ` then @session:ops/abc").map(\.reference.sessionID) == ["abc"])
    }

    @Test func linkifyMakesMarkdownLinksAndLeavesCodeAlone() {
        let text = "See @session:ops/abc and `@session:ops/abc`."
        #expect(
            SessionLink.linkified(text)
                == "See [@session:ops/abc](simplyhermes://session/ops/abc) and `@session:ops/abc`.")
        #expect(SessionLink.linkified("No links here.") == "No links here.")
    }
}
