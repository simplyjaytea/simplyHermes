import Testing

@testable import HermesKit

@Suite struct MessageQueueTests {
    @Test func keepsOrderAndSkipsBlankText() {
        var queue = MessageQueue()
        queue.enqueue("one")
        #expect(queue.enqueue("   ") == nil)
        queue.enqueue("two")
        #expect(queue.entries.map(\.text) == ["one", "two"])
        #expect(queue.takeNext()?.text == "one")
        #expect(queue.entries.map(\.text) == ["two"])
    }

    @Test func editsMovesAndRemoves() throws {
        var queue = MessageQueue()
        let first = try #require(queue.enqueue("a1") as Int?)
        let second = try #require(queue.enqueue("b2") as Int?)
        let third = try #require(queue.enqueue("c3") as Int?)
        queue.edit(first, to: " a1 edited ")
        queue.move(third, to: 0)
        #expect(queue.entries.map(\.text) == ["c3", "a1 edited", "b2"])
        queue.remove(second)
        queue.edit(first, to: "")
        #expect(queue.entries.map(\.text) == ["c3"])
        queue.move(third, to: 99)
        #expect(queue.entries.count == 1)
    }

    @Test func pausedQueueGivesNothing() {
        var queue = MessageQueue()
        queue.enqueue("held")
        queue.isPaused = true
        #expect(queue.takeNext() == nil)
        queue.isPaused = false
        #expect(queue.takeNext()?.text == "held")
    }
}
