import Testing

@testable import HermesKit

@Suite struct ComposerHistoryTests {
    @Test func rememberTrimsAndSkipsBlankMessages() {
        var history = ComposerHistory()
        history.remember("  first  ")
        history.remember("   ")
        history.remember("second")
        #expect(history.sent == ["first", "second"])
    }

    @Test func rememberKeepsOnlyTheNewestMessages() {
        var history = ComposerHistory()
        for index in 0..<(ComposerHistory.limit + 5) {
            history.remember("message \(index)")
        }
        #expect(history.sent.count == ComposerHistory.limit)
        #expect(history.sent.first == "message 5")
    }

    @Test func upStartsFromAnEmptyFieldAndWalksBack() {
        var history = ComposerHistory()
        history.remember("one")
        history.remember("two")
        #expect(history.step(.older, current: "") == "two")
        #expect(history.step(.older, current: "two") == "one")
        #expect(history.step(.older, current: "one") == "one")
    }

    @Test func upDoesNothingWhileTheFieldHoldsText() {
        var history = ComposerHistory()
        history.remember("one")
        #expect(history.step(.older, current: "draft") == nil)
        #expect(history.position == nil)
    }

    @Test func downPastTheNewestMessageRestoresTheOwnText() {
        var history = ComposerHistory()
        history.remember("one")
        history.remember("two")
        _ = history.step(.older, current: "")
        _ = history.step(.older, current: "two")
        #expect(history.step(.newer, current: "one") == "two")
        #expect(history.step(.newer, current: "two") == "")
        #expect(history.position == nil)
    }

    @Test func editingAnEntryEndsTheWalk() {
        var history = ComposerHistory()
        history.remember("one")
        _ = history.step(.older, current: "")
        history.noteEdit("one, changed")
        #expect(history.position == nil)
        #expect(history.step(.older, current: "one, changed") == nil)
    }

    @Test func showingAnEntryKeepsTheWalk() {
        var history = ComposerHistory()
        history.remember("one")
        _ = history.step(.older, current: "")
        history.noteEdit("one")
        #expect(history.position == 0)
    }

    @Test func clearedTextIsTakenOnce() {
        var history = ComposerHistory()
        history.keepCleared("")
        #expect(history.takeCleared() == nil)
        history.keepCleared("half a thought")
        #expect(history.takeCleared() == "half a thought")
        #expect(history.takeCleared() == nil)
    }
}
