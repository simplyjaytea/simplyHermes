import HermesKit
@testable import HermesUI
import Testing

@MainActor
struct ToolOutputTests {
    @Test func placeholderToolMessageKeepsCommandAndText() {
        let message = ShellMessage(id: "tool-1", kind: .tool(command: "ls"), text: "a\nb")

        #expect(ToolOutput(message: message) == ToolOutput(id: "tool-1", command: "ls", isDone: true, text: "a\nb"))
    }

    @Test func otherPlaceholderMessagesHaveNoToolOutput() {
        #expect(ToolOutput(message: ShellMessage(id: "reply-1", kind: .assistant, text: "Hi")) == nil)
    }
}
