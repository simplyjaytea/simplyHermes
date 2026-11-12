import Foundation
import GRDB
import Testing

@testable import HermesKit

/// Records the instructions each reply was asked with.
private final class InstructionsRecorder: LocalChatAnswerer, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    var availability: LocalModelAvailability { .available }

    var instructions: [String] { lock.withLock { seen } }

    func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
        lock.withLock { seen.append(instructions) }
        return LocalAnswer(text: "ok", answeredBy: .apple)
    }
}

struct LocalMemoryRulesTests {
    private func memory(_ text: String, pinned: Bool = false, at seconds: TimeInterval) -> LocalMemory {
        LocalMemory(text: text, isPinned: pinned, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func blankAndTooLongTextIsRefused() throws {
        #expect(throws: LocalMemoryError.empty) { try LocalMemoryRules.validated(" \n\t ") }
        #expect(throws: LocalMemoryError.tooLong) {
            try LocalMemoryRules.validated(String(repeating: "a", count: LocalMemoryRules.itemLimit + 1))
        }
        #expect(try LocalMemoryRules.validated("  I'm vegetarian \n") == "I'm vegetarian")
    }

    @Test func pinnedFirstThenNewestFirst() {
        let old = memory("old", at: 1)
        let new = memory("new", at: 3)
        let pinned = memory("pinned", pinned: true, at: 0)
        #expect(LocalMemoryRules.selection([old, new, pinned]).map(\.text) == ["pinned", "new", "old"])
    }

    @Test func theBudgetSkipsWhatDoesNotFitButKeepsShorterOnes() {
        let long = memory(String(repeating: "x", count: 90), at: 3)
        let short = memory("short", at: 2)
        let other = memory(String(repeating: "y", count: 50), at: 1)
        // 93 + 8 = 101 fits in 110; the 53-character one does not.
        #expect(LocalMemoryRules.selection([long, short, other], budget: 110).map(\.text) == [long.text, "short"])
        #expect(LocalMemoryRules.selection([long], budget: 10).isEmpty)
    }

    @Test func theInstructionsBlockListsTheMemoriesOrIsEmpty() {
        #expect(LocalMemoryRules.instructionsBlock([]).isEmpty)
        let block = LocalMemoryRules.instructionsBlock([memory("I'm vegetarian", at: 1)])
        #expect(block.hasSuffix("\n- I'm vegetarian"))
        #expect(block.hasPrefix("What you know about the user"))
    }

    @Test func withoutMemoryTheInstructionsAreUnchanged() {
        #expect(LocalChatController.instructions(memory: []) == LocalChatController.instructions)
    }
}

struct LocalMemoryStoreTests {
    @Test func memoriesSurviveAReopenWithTheirPinsAndOrder() async throws {
        let url = try temporaryDatabaseURL()
        let saved: LocalMemory
        do {
            let store = try HermesCache(url: url).localMemory
            try await store.save("older", source: .user, at: Date(timeIntervalSince1970: 1))
            saved = try await store.save("  newer  ", source: .model, at: Date(timeIntervalSince1970: 2))
            let pinned = try await store.save("pinned", source: .user, at: Date(timeIntervalSince1970: 0))
            try await store.setPinned(pinned.id, true)
        }
        let reopened = GRDBLocalMemoryStore(database: try DatabaseQueue(path: url.path))
        let all = try await reopened.memories()
        #expect(all.map(\.text) == ["pinned", "newer", "older"])
        #expect(all[0].isPinned)
        #expect(all[1].id == saved.id)
        #expect(all[1].source == .model)
    }

    @Test func editDeleteAndDeleteAll() async throws {
        let store = try HermesCache().localMemory
        let first = try await store.save("first", source: .user, at: localChatStart)
        try await store.save("second", source: .user, at: localChatStart)
        try await store.update(first.id, text: "first, edited")
        #expect(try await store.memories().map(\.text).contains("first, edited"))
        try await store.delete(first.id)
        try await store.delete(first.id)  // a second delete (Undo race, double tap) does nothing
        #expect(try await store.memories().map(\.text) == ["second"])
        try await store.deleteAll()
        #expect(try await store.memories().isEmpty)
    }

    @Test func invalidOrMissingChangesAreRefused() async throws {
        let store = try HermesCache().localMemory
        await #expect(throws: LocalMemoryError.empty) { try await store.save("   ", source: .user, at: localChatStart) }
        let kept = try await store.save("kept", source: .user, at: localChatStart)
        await #expect(throws: LocalMemoryError.empty) { try await store.update(kept.id, text: "") }
        await #expect(throws: LocalMemoryError.notFound) { try await store.update(UUID(), text: "x") }
        await #expect(throws: LocalMemoryError.notFound) { try await store.setPinned(UUID(), true) }
        #expect(try await store.memories().map(\.text) == ["kept"])
    }

    @Test func theMigrationAddsOnlyTheMemoryTable() async throws {
        let url = try temporaryDatabaseURL()
        _ = try HermesCache(url: url)
        #expect(try tableNames(at: url).contains("local_memory"))
    }
}

struct LocalChatMemoryTests {
    @Test func savedMemoryReachesTheModelAndADeletedOneStopsAtOnce() async throws {
        let cache = try HermesCache()
        let chats = cache.localChats
        let memory = cache.localMemory
        let note = try await memory.save("I'm vegetarian", source: .user, at: localChatStart)
        let recorder = InstructionsRecorder()
        let controller = await LocalChatController(
            store: chats, answerer: { recorder }, chatID: UUID(),
            memory: { (try? await memory.memories()) ?? [] }, now: { localChatStart })

        await controller.send("Suggest a dinner")
        #expect(recorder.instructions.last?.contains("- I'm vegetarian") == true)
        #expect(recorder.instructions.last?.hasPrefix(LocalChatController.instructions) == true)

        try await memory.delete(note.id)
        await controller.send("And tomorrow?")
        #expect(recorder.instructions.count == 2)
        #expect(recorder.instructions.last == LocalChatController.instructions, "Deleted memory is gone at once")
    }
}
