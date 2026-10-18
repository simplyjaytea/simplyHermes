import Testing
@testable import HermesKit
@testable import HermesUI

@MainActor
struct ToolOutputTests {
    @Test func placeholderToolMessageKeepsCommandAndText() {
        let message = ShellMessage(id: "tool-1", kind: .tool(command: "ls"), text: "a\nb")

        #expect(ToolOutput(message: message) == ToolOutput(id: "tool-1", command: "ls", isDone: true, text: "a\nb"))
    }

    @Test func otherPlaceholderMessagesHaveNoToolOutput() {
        #expect(ToolOutput(message: ShellMessage(id: "reply-1", kind: .assistant, text: "Hi")) == nil)
    }

    /// A live `tool.complete` carries the output only in `result` (Fixtures/chat_tool_call.jsonl, i=23).
    @Test func liveToolCompleteShowsTheOutputFromResult() {
        var entry = ToolEntry(name: "terminal", phase: .completed)
        entry.context = "echo testbed-tool-ok"
        let result: JSONValue = ["output": "testbed-tool-ok", "exit_code": 0, "error": nil]
        entry.result = result
        let item = TranscriptItem(id: "tool-call_11438fb80bf2", content: .tool(entry))

        #expect(ToolOutput(item: item)?.text == "testbed-tool-ok")
    }

    @Test func resultTextWinsOverTheResultOutput() {
        var entry = ToolEntry(name: "terminal", phase: .completed)
        entry.resultText = "from history"
        let result: JSONValue = ["output": "from result"]
        entry.result = result

        #expect(ToolOutput(item: TranscriptItem(id: "row-1", content: .tool(entry)))?.text == "from history")
    }
}
