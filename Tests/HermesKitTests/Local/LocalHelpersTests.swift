import Testing

@testable import HermesKit

private final class MockExecutor: LocalModelExecutor, @unchecked Sendable {
    var availability: LocalModelAvailability = .available
    var answer: @Sendable (String) -> String = { _ in "answer" }
    var failure = false
    private(set) var prompts: [String] = []

    func respond(instructions: String, prompt: String) async throws -> String {
        prompts.append(prompt)
        if failure { throw CancellationError() }
        return answer(prompt)
    }
}

struct LocalHelpersTests {
    @Test func titleIsCleanedAndShort() async {
        let mock = MockExecutor()
        mock.answer = { _ in "\"Fixing the login bug.\"\nextra line" }
        let title = await LocalHelpers(executor: mock).title(userText: "my login is broken")
        #expect(title == "Fixing the login bug")
    }

    @Test func unavailableModelReturnsNilWithoutCalling() async {
        let mock = MockExecutor()
        mock.availability = .unavailable(.disabled)
        let helpers = LocalHelpers(executor: mock)
        #expect(await helpers.title(userText: "hi") == nil)
        #expect(await helpers.polish("hi") == nil)
        #expect(mock.prompts.isEmpty)
        #expect(!helpers.isAvailable)
    }

    @Test func failureAndBlankAnswersGiveNil() async {
        let mock = MockExecutor()
        mock.failure = true
        #expect(await LocalHelpers(executor: mock).polish("hello") == nil)
        mock.failure = false
        mock.answer = { _ in "   " }
        #expect(await LocalHelpers(executor: mock).polish("hello") == nil)
    }

    @Test func shortTextIsSummarizedOnce() async {
        let mock = MockExecutor()
        let result = await LocalHelpers(executor: mock).summary(of: "short text")
        #expect(result == "answer")
        #expect(mock.prompts == ["short text"])
    }

    @Test func longTextIsSummarizedInPiecesThenJoined() async {
        let mock = MockExecutor()
        mock.answer = { _ in "part" }
        let paragraph = String(repeating: "word ", count: 600)
        let text = [paragraph, paragraph, paragraph].joined(separator: "\n\n")
        _ = await LocalHelpers(executor: mock).summary(of: text)
        #expect(mock.prompts.count >= 3)
        #expect(mock.prompts.last?.contains("part\n\npart") == true)
    }

    @Test func chunksPreferBlankLinesAndKeepAllText() {
        let text = "aaaa\n\nbbbb\n\ncccc"
        let pieces = LocalHelpers.chunks(of: text, size: 8)
        #expect(pieces == ["aaaa", "bbbb", "cccc"])
        #expect(LocalHelpers.chunks(of: "  ", size: 8).isEmpty)
    }

    @Test func titleIsCutAtTheLimit() {
        let long = String(repeating: "a", count: 100)
        #expect(LocalHelpers.cleanTitle(long)?.count == LocalHelpers.maxTitleLength)
    }
}
