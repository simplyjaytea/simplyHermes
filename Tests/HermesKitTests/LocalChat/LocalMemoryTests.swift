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
        // Up to this migration only, so a later migration's tables (#145's placeholder_chats) don't count here.
        let url = try temporaryDatabaseURL()
        _ = try HermesCache.openSchema(url: url, upTo: "local-memory-v1")
        let before = try temporaryDatabaseURL()
        _ = try HermesCache.openSchema(url: before, upTo: "local-chat-v1")
        let added = Set(try tableNames(at: url)).subtracting(try tableNames(at: before))
        #expect(added == ["local_memory"], "the memory migration adds exactly one table")
        #expect(Set(try tableNames(at: before)).isSubset(of: try tableNames(at: url)), "and drops none")
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

struct LocalMemoryUndoTests {
    @Test func undoOfASaveDeletesIt() async throws {
        let store = try HermesCache().localMemory
        let saved = try await store.save("I'm vegetarian", source: .model, at: localChatStart)
        try await LocalMemoryChange.saved(saved).undo(in: store)
        #expect(try await store.memories().isEmpty)
    }

    @Test func undoOfADeleteRestoresItExactlyWithItsPlace() async throws {
        let store = try HermesCache().localMemory
        let older = try await store.save("older", source: .user, at: Date(timeIntervalSince1970: 1))
        try await store.setPinned(older.id, true)
        try await store.save("newer", source: .user, at: Date(timeIntervalSince1970: 2))
        let before = try await store.memories()
        let pinned = try #require(before.first)
        try await store.delete(pinned.id)
        try await LocalMemoryChange.deleted(pinned).undo(in: store)
        #expect(try await store.memories() == before, "same id, pin, source, time and order")
    }

    @Test func undoOfDeleteAllBringsEveryMemoryBack() async throws {
        let store = try HermesCache().localMemory
        try await store.save("one", source: .user, at: Date(timeIntervalSince1970: 1))
        try await store.save("two", source: .model, at: Date(timeIntervalSince1970: 2))
        let before = try await store.memories()
        try await store.deleteAll()
        let change = LocalMemoryChange.deletedAll(before)
        #expect(change.summary == "2 memories deleted")
        try await change.undo(in: store)
        #expect(try await store.memories() == before)
    }

    @Test func undoingTwiceIsHarmless() async throws {
        let store = try HermesCache().localMemory
        let saved = try await store.save("x", source: .user, at: localChatStart)
        try await store.delete(saved.id)
        try await LocalMemoryChange.deleted(saved).undo(in: store)
        try await LocalMemoryChange.deleted(saved).undo(in: store)
        #expect(try await store.memories().map(\.id) == [saved.id])
    }
}

struct LocalMemoryDeleteAllTests {
    /// Review m1: Undo of Delete all brings back exactly what was deleted, also when the screen's list is out of date.
    @Test func deleteAllReturnsWhatItReallyDeleted() async throws {
        let store = try HermesCache().localMemory
        try await store.save("on screen", source: .user, at: Date(timeIntervalSince1970: 1))
        let screensCopy = try await store.memories()
        try await store.save("saved meanwhile", source: .model, at: Date(timeIntervalSince1970: 2))
        let deleted = try await store.deleteAll()
        #expect(Set(deleted.map(\.text)) == ["on screen", "saved meanwhile"])
        #expect(screensCopy.count == 1)
        try await LocalMemoryChange.deletedAll(deleted).undo(in: store)
        #expect(Set(try await store.memories().map(\.text)) == ["on screen", "saved meanwhile"])
    }

    /// Review m2: a restore is all or none. A trigger makes the table refuse the second row.
    @Test func aRestoreThatFailsPartWayRestoresNothing() async throws {
        let queue = try DatabaseQueue()
        try HermesCache.migrator.migrate(queue)
        try await queue.write { handle in
            try handle.execute(
                sql: """
                    CREATE TRIGGER refuse BEFORE INSERT ON local_memory WHEN NEW.text = 'boom'
                    BEGIN SELECT RAISE(ABORT, 'refused'); END;
                    """)
        }
        let store = GRDBLocalMemoryStore(database: queue)
        let good = LocalMemory(text: "good", createdAt: localChatStart)
        let refused = LocalMemory(text: "boom", createdAt: localChatStart)
        await #expect(throws: (any Error).self) { try await store.restore([good, refused]) }
        #expect(try await store.memories().isEmpty, "the first row is rolled back too")
        try await store.restore([good])
        #expect(try await store.memories().map(\.text) == ["good"])
    }
}

struct RememberThisTests {
    @Test func aMessageIsSavedTrimmedAndCutToTheLimit() throws {
        #expect(LocalMemoryRules.excerpt(of: "  I'm vegetarian \n") == "I'm vegetarian")
        #expect(LocalMemoryRules.excerpt(of: " \n ") == nil)
        let long = String(repeating: "word ", count: 200)
        let cut = try #require(LocalMemoryRules.excerpt(of: long))
        #expect(cut.count <= LocalMemoryRules.itemLimit)
        #expect(cut.hasSuffix("…"))
        #expect(try LocalMemoryRules.validated(cut) == cut, "an excerpt always passes validation")
    }
}
