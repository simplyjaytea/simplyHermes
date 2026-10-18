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
}
