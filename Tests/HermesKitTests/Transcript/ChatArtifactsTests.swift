import HermesKit
import Testing

@Suite struct ChatArtifactsTests {
    @Test func imageToolResultGivesItsImage() {
        let result: JSONValue = .object(["image": .string("/opt/hermes/cache/out.png"), "success": .bool(true)])

        #expect(ChatArtifacts.image(toolName: "image_generate", result: result) == "/opt/hermes/cache/out.png")
    }

    @Test func urlImagesCountToo() {
        let result: JSONValue = .object(["image": .string("https://images.example/cat.png")])

        #expect(ChatArtifacts.image(toolName: "image_generate", result: result) == "https://images.example/cat.png")
    }

    @Test func failedGenerationGivesNoArtifact() {
        let result: JSONValue = .object(["image": .string("/opt/hermes/cache/out.png"), "success": .bool(false)])

        #expect(ChatArtifacts.image(toolName: "image_generate", result: result) == nil)
    }

    @Test func otherToolsGiveNoArtifact() {
        let result: JSONValue = .object(["image": .string("/opt/hermes/README.md")])

        #expect(ChatArtifacts.image(toolName: "terminal", result: result) == nil)
        #expect(ChatArtifacts.image(toolName: "image_generate", result: nil) == nil)
        #expect(ChatArtifacts.image(toolName: "image_generate", result: .object([:])) == nil)
    }

    /// A tool row as `session.resume` sends it: the result is JSON inside the text, and there is no `result`.
    private func historyRow(_ rowID: Int, tool: String, text: String) throws -> TranscriptMessage {
        let row: JSONValue = [
            "role": "tool", "name": .string(tool), "tool_call_id": .string("call_\(rowID)"), "row_id": .int(rowID),
            "text": .string(text),
        ]
        return try row.decode(TranscriptMessage.self)
    }

    @Test func historyRowsGiveTheirImagesFromTheResultText() throws {
        let cat = #"{"success": true, "image": "/opt/hermes/cache/cat.png"}"#
        let dog = #"{"success": true, "image": "https://images.example/dog.png"}"#
        let failed = #"{"success": false, "image": "/opt/hermes/cache/failed.png"}"#
        let rows = [
            try historyRow(1, tool: "image_generate", text: cat),
            try historyRow(2, tool: "image_generate", text: dog),
            try historyRow(3, tool: "image_generate", text: failed),
            try historyRow(4, tool: "image_generate", text: "Could not draw that."),
            try historyRow(5, tool: "terminal", text: cat),
        ]
        var state = TranscriptState(liveSessionID: "abcd1234")
        state.apply(.history(rows))

        let artifacts = ChatArtifacts.all(in: state.items)

        #expect(artifacts.map(\.id) == ["row-1", "row-2"])
        #expect(artifacts.map(\.image) == ["/opt/hermes/cache/cat.png", "https://images.example/dog.png"])
    }

    @Test func aLiveRowGivesItsImageFromTheResult() throws {
        let event: JSONValue = [
            "type": "tool.complete", "session_id": "abcd1234", "seq": 1,
            "payload": [
                "tool_id": "call_1", "name": "image_generate",
                "result": ["success": true, "image": "/opt/hermes/cache/live.png"],
            ],
        ]
        var state = TranscriptState(liveSessionID: "abcd1234")
        state.apply(.event(try event.decode(GatewayEventEnvelope.self), replayed: false))

        let artifacts = ChatArtifacts.all(in: state.items)

        #expect(artifacts.map(\.id) == ["tool-call_1"])
        #expect(artifacts.map(\.image) == ["/opt/hermes/cache/live.png"])
    }
}
