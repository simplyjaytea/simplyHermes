import Foundation
import Testing

@testable import HermesKit

/// Memory phase 2: the model saves on its own with Undo, and asks first when the turn read a file.
struct LocalToolsTests {
    private let block = """
        ```tool_call
        {"name": "memory_save", "arguments": {"text": "The user is vegetarian."}}
        ```
        """

    // MARK: The guard (spec section 7, test 3)

    /// The tool set is closed and reviewed. Adding a tool fails here until this list is updated in review.
    @Test func theToolSetIsTheReviewedList() {
        #expect(LocalToolName.allCases.map(\.rawValue) == ["memory_save"])
    }

    // MARK: Parsing

    @Test func aWholeToolCallBlockIsACall() {
        #expect(
            LocalToolCall.parse(block)
                == LocalToolCall(name: .memorySave, arguments: ["text": "The user is vegetarian."]))
    }

    @Test(arguments: [
        "Sure! " + "```tool_call\n{\"name\": \"memory_save\", \"arguments\": {\"text\": \"x\"}}\n```",
        "```tool_call\n{\"name\": \"shell\", \"arguments\": {\"cmd\": \"ls\"}}\n```",
        "```tool_call\n{\"name\": \"memory_save\", \"arguments\": {\"text\": 3}}\n```",
        "```tool_call\nnot json\n```",
        "```tool_call\n{\"name\": \"memory_save\", \"arguments\": {}, \"extra\": 1}\n```",
        "```json\n{\"name\": \"memory_save\", \"arguments\": {\"text\": \"x\"}}\n```",
        "Plain answer.",
    ])
    func anythingElseIsText(answer: String) {
        #expect(LocalToolCall.parse(answer) == nil)
    }

    // MARK: The save rule

    @Test func aSaveIsImmediateUnlessTheTurnReadAFile() {
        #expect(LocalMemoryAutoSave.decide(text: " Likes tea ", turnReadAFile: false) == .save("Likes tea"))
        #expect(LocalMemoryAutoSave.decide(text: "Likes tea", turnReadAFile: true) == .askFirst("Likes tea"))
        #expect(LocalMemoryAutoSave.decide(text: "  ", turnReadAFile: false) == .refuse(.empty))
        #expect(LocalMemoryAutoSave.decide(text: nil, turnReadAFile: false) == .refuse(.empty))
        let long = String(repeating: "a", count: LocalMemoryRules.itemLimit + 1)
        #expect(LocalMemoryAutoSave.decide(text: long, turnReadAFile: false) == .refuse(.tooLong))
    }
}

/// The controller runs memory_save for a model that supports tools.
struct LocalChatToolLoopTests {
    /// Answers from a script, one answer per call, and records the prompts and instructions.
    private final class Script: LocalChatAnswerer, @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String]
        private(set) var prompts: [String] = []
        private(set) var instructions: [String] = []
        let supportsTools: Bool
        var availability: LocalModelAvailability { .available }

        init(_ answers: [String], tools: Bool = true) {
            self.answers = answers
            supportsTools = tools
        }

        func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
            let next: String = lock.withLock {
                prompts.append(prompt)
                self.instructions.append(instructions)
                return answers.isEmpty ? "" : answers.removeFirst()
            }
            return LocalAnswer(text: next, answeredBy: .apple)
        }

        var calls: Int { lock.withLock { prompts.count } }
    }

    private let save = """
        ```tool_call
        {"name": "memory_save", "arguments": {"text": "The user is vegetarian."}}
        ```
        """

    @Test func theModelSavesOnItsOwnWithUndoThenAnswers() async throws {
        let cache = try HermesCache()
        let script = Script([save, "Noted! Here are vegetarian dinners."])
        let controller = await LocalChatController(
            store: cache.localChats, answerer: { script }, chatID: UUID(),
            memory: { (try? await cache.localMemory.memories()) ?? [] }, memoryStore: cache.localMemory,
            now: { localChatStart })
        await controller.send("I'm vegetarian. Dinner ideas?")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.last?.text == "Noted! Here are vegetarian dinners.", "the final answer, not the call")
        #expect(!snapshot.messages.contains { $0.text.contains("tool_call") }, "the call itself is never a reply")
        #expect(try await cache.localMemory.memories().map(\.text) == ["The user is vegetarian."])
        #expect(try await cache.localMemory.memories().first?.source == .model)
        guard case .saved = snapshot.memoryChange else {
            Issue.record("expected an Undo for the save")
            return
        }
        #expect(script.instructions.first?.contains("memory_save") == true)
        #expect(script.prompts.last?.contains("Saved to the user's memory") == true)

        await controller.undoMemoryChange()
        #expect(try await cache.localMemory.memories().isEmpty, "Undo takes it back")
        #expect(await controller.snapshot.memoryChange == nil)
    }

    @Test func aModelWithoutToolsIsNeverOfferedThem() async throws {
        let cache = try HermesCache()
        let script = Script([save], tools: false)
        let controller = await LocalChatController(
            store: cache.localChats, answerer: { script }, chatID: UUID(), memoryStore: cache.localMemory,
            now: { localChatStart })
        await controller.send("I'm vegetarian")
        #expect(script.instructions.first?.contains("memory_save") == false)
        #expect(try await cache.localMemory.memories().isEmpty)
        #expect(await controller.snapshot.messages.last?.text == save, "shown as the model wrote it")
    }

    @Test func endlessToolCallsStopWithNoReplyAndNothingMadeUp() async throws {
        let cache = try HermesCache()
        let script = Script(Array(repeating: save, count: 20))
        let controller = await LocalChatController(
            store: cache.localChats, answerer: { script }, chatID: UUID(), memoryStore: cache.localMemory,
            now: { localChatStart })
        await controller.send("hi")
        let snapshot = await controller.snapshot
        #expect(script.calls == LocalChatController.toolCallLimit + 1)
        #expect(snapshot.messages.map(\.text) == ["hi"], "no assistant row is invented")
        #expect(snapshot.failure == .modelFailed)
        #expect(snapshot.unansweredIDs == [1], "Retry is offered")
    }

    @Test func aProposalIsSavedOnlyOnYes() async throws {
        let cache = try HermesCache()
        let script = Script([])
        let controller = await LocalChatController(
            store: cache.localChats, answerer: { script }, chatID: UUID(), memoryStore: cache.localMemory,
            now: { localChatStart })
        await controller.proposeForTest("From a file: likes tea")
        #expect(await controller.snapshot.memoryProposal == "From a file: likes tea")
        await controller.declineMemoryProposal()
        #expect(try await cache.localMemory.memories().isEmpty)
        await controller.proposeForTest("From a file: likes tea")
        await controller.confirmMemoryProposal()
        #expect(try await cache.localMemory.memories().map(\.text) == ["From a file: likes tea"])
    }
}

extension LocalChatController {
    /// Phase 3 (files) sets the "read a file" flag; until then a test puts a proposal in place directly.
    func proposeForTest(_ text: String) {
        setProposalForTesting(text)
    }
}
