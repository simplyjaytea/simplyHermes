import Testing

@testable import HermesKit

struct TaskProgressTests {
    private func item(_ text: String, _ status: String) -> JSONValue {
        .object(["content": .string(text), "status": .string(status)])
    }

    @Test func countsFinishedAndFindsCurrent() throws {
        let raw = [item("a", "completed"), item("b", "in_progress"), item("c", "pending")]
        let progress = try #require(TaskProgress(raw))
        #expect(progress.finished == 1)
        #expect(progress.summary == "1 of 3")
        #expect(progress.current?.text == "b")
        #expect(!progress.isComplete)
    }

    @Test func fallsBackToFirstPending() throws {
        let progress = try #require(TaskProgress([item("a", "done"), item("b", "pending")]))
        #expect(progress.current?.text == "b")
    }

    @Test func completeWhenAllDoneOrCancelled() throws {
        let progress = try #require(TaskProgress([item("a", "done"), item("b", "cancelled")]))
        #expect(progress.isComplete)
        #expect(progress.current == nil)
    }

    @Test func skipsUnreadableItemsAndReturnsNilWhenEmpty() {
        #expect(TaskProgress([.string("x"), .object([:])]) == nil)
        #expect(TaskProgress([]) == nil)
    }
}
