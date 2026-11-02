import HermesKit
import Testing

@testable import HermesUI

/// WP-8 (Poppy's M3): "Continue in a new Local chat" moves the draft. The new chat gets the text and the online chat
/// no longer holds it, so the same text can't be sent from both. The online chat keeps its messages and attachments.
@MainActor
struct ContinueDraftTests {
    /// Never answers. The test only checks where the draft goes, so no reply should be made.
    private struct Silent: LocalModelExecutor {
        var availability: LocalModelAvailability { .available }

        func respond(instructions: String, prompt: String) async throws -> String { "" }
    }

    @Test func continueMovesTheDraftToTheNewLocalChat() throws {
        let saved = LocalChatServices.shared
        defer { LocalChatServices.shared = saved }
        LocalChatServices.install(
            cache: try HermesCache(),
            answerer: {
                FixedModelAnswerer(identity: .apple, executor: Silent())
            })
        let model = ShellModel(sessions: [], selectedSessionID: "server-1")
        model.drafts["server-1"] = "ping"

        model.continueInNewLocalChat(carrying: "ping")

        let newID = try #require(model.selectedSessionID)
        #expect(newID != "server-1")
        #expect(newID.hasPrefix("local-"))
        #expect(model.drafts[newID] == "ping")
        #expect(model.drafts["server-1"] == nil, "The online chat must not keep the draft")
    }
}
