import Testing

@testable import HermesKit

struct NewReplyDotTests {
    private func assistant(_ id: String, _ text: String, kind: String? = nil) -> TranscriptItem {
        TranscriptItem(
            id: id, content: .assistant(AssistantEntry(text: text, isStreaming: true, displayKind: kind)))
    }

    private func user(_ id: String, _ text: String) -> TranscriptItem {
        TranscriptItem(id: id, content: .user(UserEntry(text: text, delivery: .sent)))
    }

    @Test func historyAlreadyInTheChatNeverLightsIt() {
        var dot = NewReplyDot()
        #expect(dot.update(chatID: "c1", items: [assistant("a1", "old reply")], isFollowing: false) == nil)
        #expect(!dot.isShowing)
    }

    @Test func newTextWhileScrolledUpLightsItAndAnnouncesOncePerReply() {
        var dot = NewReplyDot()
        _ = dot.update(chatID: "c1", items: [user("u1", "hi")], isFollowing: false)
        #expect(dot.update(chatID: "c1", items: [user("u1", "hi"), assistant("a1", "He")], isFollowing: false) == "a1")
        #expect(dot.isShowing)
        #expect(
            dot.update(chatID: "c1", items: [user("u1", "hi"), assistant("a1", "Hello")], isFollowing: false) == nil,
            "more text of the same reply is not announced again")
        #expect(dot.isShowing)
        let next = [user("u1", "hi"), assistant("a1", "Hello"), assistant("a2", "Again")]
        #expect(dot.update(chatID: "c1", items: next, isFollowing: false) == "a2", "a new reply is announced")
    }

    @Test func atTheBottomNothingShows() {
        var dot = NewReplyDot()
        _ = dot.update(chatID: "c1", items: [], isFollowing: true)
        #expect(dot.update(chatID: "c1", items: [assistant("a1", "Hello")], isFollowing: true) == nil)
        #expect(!dot.isShowing)
    }

    @Test func reachingTheBottomClearsItAndScrollingUpAgainWaitsForNewText() {
        var dot = NewReplyDot()
        _ = dot.update(chatID: "c1", items: [], isFollowing: false)
        _ = dot.update(chatID: "c1", items: [assistant("a1", "Hi")], isFollowing: false)
        dot.reachedBottom()
        #expect(!dot.isShowing)
        #expect(dot.update(chatID: "c1", items: [assistant("a1", "Hi")], isFollowing: false) == nil)
        #expect(!dot.isShowing, "no new text, no dot")
    }

    @Test func userRowsToolsNoticesAndDisclosuresNeverLightIt() {
        var dot = NewReplyDot()
        _ = dot.update(chatID: "c1", items: [], isFollowing: false)
        let items: [TranscriptItem] = [
            user("u1", "hello"),
            TranscriptItem(id: "n1", content: .other(role: "system", text: "Reconnected")),
            assistant("cron", "Nightly report", kind: "cron"),
        ]
        #expect(dot.update(chatID: "c1", items: items, isFollowing: false) == nil)
        #expect(!dot.isShowing)
    }

    /// Review m1 on #141: the chat screen is reused across chats, so switching chats while scrolled up must not count
    /// the next chat's history as new.
    @Test func switchingChatsStartsOverWithoutADot() {
        var dot = NewReplyDot()
        _ = dot.update(chatID: "c1", items: [], isFollowing: false)
        #expect(dot.update(chatID: "c1", items: [assistant("a1", "Hi")], isFollowing: false) == "a1")
        #expect(dot.isShowing)
        let other = [user("u9", "old"), assistant("b1", "an old reply"), assistant("b2", "another")]
        #expect(dot.update(chatID: "c2", items: other, isFollowing: false) == nil, "nothing announced on a switch")
        #expect(!dot.isShowing, "the other chat's dot doesn't carry over")
        #expect(dot.update(chatID: "c2", items: other + [assistant("b3", "new")], isFollowing: false) == "b3")
    }
}
