import Testing

@testable import HermesKit

@Suite struct TranscriptSearchTests {
    private func user(_ id: String, _ text: String) -> TranscriptItem {
        TranscriptItem(id: id, content: .user(UserEntry(text: text, delivery: .sent)))
    }

    private func assistant(_ id: String, _ text: String, reasoning: String? = nil) -> TranscriptItem {
        TranscriptItem(
            id: id, content: .assistant(AssistantEntry(text: text, reasoning: reasoning, isStreaming: false)))
    }

    @Test func matchesIgnoreCaseAndAccents() {
        let items = [user("a", "Deploy the Café"), assistant("b", "done"), assistant("c", "cafe is live")]
        #expect(TranscriptSearch.matchingIDs(in: items, query: "CAFE") == ["a", "c"])
    }

    @Test func blankQueryMatchesNothing() {
        #expect(TranscriptSearch.matchingIDs(in: [user("a", "x")], query: "  ").isEmpty)
    }

    @Test func looksThroughReasoningAndTools() {
        var tool = ToolEntry(name: "terminal", phase: .completed)
        tool.resultText = "permission denied"
        let items = [
            assistant("a", "ok", reasoning: "think about permissions"),
            TranscriptItem(id: "t", content: .tool(tool)),
        ]
        #expect(TranscriptSearch.matchingIDs(in: items, query: "permission") == ["a", "t"])
    }

    @Test func nextAndPreviousWrap() {
        let matches = ["a", "b", "c"]
        #expect(TranscriptSearch.next(after: nil, in: matches) == "a")
        #expect(TranscriptSearch.next(after: "c", in: matches) == "a")
        #expect(TranscriptSearch.previous(before: nil, in: matches) == "c")
        #expect(TranscriptSearch.previous(before: "a", in: matches) == "c")
        #expect(TranscriptSearch.next(after: "a", in: []) == nil)
    }
}
