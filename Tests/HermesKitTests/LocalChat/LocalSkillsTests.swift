import Foundation
import Testing

@testable import HermesKit

struct LocalSkillsTests {
    @Test func theFiveBuiltInsAreTheApprovedOnes() {
        #expect(
            LocalSkill.builtIn.map(\.title) == [
                "Summarize", "Explain simply", "Review my writing", "Make a checklist", "Translate",
            ])
        #expect(Set(LocalSkill.builtIn.map(\.name)).count == 5, "names are unique")
        for skill in LocalSkill.builtIn {
            #expect(skill.body.count <= LocalSkill.bodyLimit)
            #expect(skill.name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        }
    }

    @Test func aSlashNameStartsASkillMessage() throws {
        let call = try #require(LocalSkillInvocation.parse("  /Summarize  the minutes below\nItem 1  "))
        #expect(call.skill.name == "summarize")
        #expect(call.message == "the minutes below\nItem 1")
        #expect(call.prompt == call.message)
        #expect(call.instructionsBlock.hasPrefix("For this message, use the skill \"Summarize\":"))
    }

    @Test func onlyTheNameMeansTheChatSoFar() throws {
        let call = try #require(LocalSkillInvocation.parse("/checklist"))
        #expect(call.message.isEmpty)
        #expect(call.prompt == "Apply this to the conversation so far.")
    }

    @Test(arguments: ["summarize this", "/unknown thing", "a /summarize in the middle", "/", "//summarize"])
    func otherMessagesAreOrdinary(text: String) {
        #expect(LocalSkillInvocation.parse(text) == nil)
    }

    @Test func completionsFollowTheTypedPrefix() {
        #expect(LocalSkillInvocation.completions("").count == 5)
        let translate = LocalSkillInvocation.completions("tr")
        #expect(translate.map(\.text) == ["/translate "])
        #expect(translate.first?.kind == "skill")
        #expect(LocalSkillInvocation.completions("make").map(\.display) == ["/checklist"], "matches the title too")
        #expect(LocalSkillInvocation.completions("zzz").isEmpty)
    }

    /// The controller gives the model the skill's body for that message and the message without the `/name`.
    @Test func aSkillMessageReachesTheModelWithItsInstructions() async throws {
        final class Recorder: LocalChatAnswerer, @unchecked Sendable {
            private let lock = NSLock()
            private var seen: [(String, String)] = []
            var availability: LocalModelAvailability { .available }
            var calls: [(instructions: String, prompt: String)] { lock.withLock { seen } }
            func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
                lock.withLock { seen.append((instructions, prompt)) }
                return LocalAnswer(text: "- point", answeredBy: .apple)
            }
        }
        let recorder = Recorder()
        let controller = await LocalChatController(
            store: try HermesCache().localChats, answerer: { recorder }, chatID: UUID(), now: { localChatStart })
        await controller.send("/summarize Long meeting notes")
        await controller.send("And thanks")
        let calls = recorder.calls
        #expect(calls.count == 2)
        #expect(calls[0].instructions.contains("Summarize the user's text"))
        #expect(calls[0].prompt.hasSuffix("Long meeting notes"))
        #expect(!calls[0].prompt.contains("/summarize"))
        #expect(!calls[1].instructions.contains("Summarize the user's text"), "a skill is for its one message")
        #expect(await controller.snapshot.messages.first?.text == "/summarize Long meeting notes", "saved as typed")
    }
}
