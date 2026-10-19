import Foundation
import HermesKit
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Suite struct EntryRouteTests {
    // MARK: Share URLs

    @Test func shareURLsRoundTrip() {
        let url = HermesURL.share("0b6c1d3a-9f2e-4c7b-8a55-1d2e3f4a5b6c")
        #expect(url.absoluteString == "simplyhermes://share/0b6c1d3a-9f2e-4c7b-8a55-1d2e3f4a5b6c")
        #expect(HermesURL.shareID(from: url) == "0b6c1d3a-9f2e-4c7b-8a55-1d2e3f4a5b6c")
        let made = ShareOutbox.makeID()
        #expect(HermesURL.shareID(from: HermesURL.share(made)) == made)
    }

    @Test func shareURLsRejectUnsafeOrForeignURLs() {
        let rejected = [
            "simplyhermes://share", "simplyhermes://share/", "simplyhermes://share/a/b",
            "simplyhermes://share/..", "simplyhermes://share/a%20b", "simplyhermes://share/a%2Fb",
            "simplyhermes://chat/abc", "simplyhermes://quick-entry", "https://share/abc", "other://share/abc",
        ]
        for text in rejected {
            #expect(HermesURL.shareID(from: URL(string: text)!) == nil, "\(text)")
        }
    }

    @Test func shareURLsDoNotLookLikeChatURLs() {
        let url = HermesURL.share("abc")
        #expect(HermesURL.chatID(from: url) == nil)
        #expect(HermesURL.shareID(from: HermesURL.chat("abc")) == nil)
    }

    // MARK: Quick Entry URLs

    @Test func quickEntryWithoutTextIsAPlainURL() {
        let url = HermesURL.quickEntry()
        #expect(url.absoluteString == "simplyhermes://quick-entry")
        #expect(HermesURL.quickEntryRoute(from: url) == QuickEntryRoute(prefill: nil))
    }

    @Test func quickEntryCarriesPrefilledText() {
        for text in ["Plan the week", "Plan the week & check mail", "a=b+c ?#", "Zürich café 東京"] {
            let url = HermesURL.quickEntry(prefill: text)
            #expect(HermesURL.quickEntryRoute(from: url) == QuickEntryRoute(prefill: text), "\(text)")
        }
        let typed = URL(string: "simplyhermes://quick-entry?text=Hello%20there")!
        #expect(HermesURL.quickEntryRoute(from: typed)?.prefill == "Hello there")
    }

    @Test func quickEntryIgnoresBlankAndOversizedText() {
        #expect(HermesURL.quickEntryRoute(from: URL(string: "simplyhermes://quick-entry?text=%20%20")!)?.prefill == nil)
        #expect(HermesURL.quickEntryRoute(from: URL(string: "simplyhermes://quick-entry?other=1")!)?.prefill == nil)
        let long = String(repeating: "x", count: QuickEntryRoute.prefillLimit + 500)
        let route = HermesURL.quickEntryRoute(from: HermesURL.quickEntry(prefill: long))
        #expect(route?.prefill?.count == QuickEntryRoute.prefillLimit)
    }

    @Test func otherURLsAreNotQuickEntry() {
        for text in [
            "simplyhermes://chat/abc", "simplyhermes://share/abc", "https://quick-entry", "other://quick-entry",
        ] {
            #expect(HermesURL.quickEntryRoute(from: URL(string: text)!) == nil, "\(text)")
        }
    }

    // MARK: Pending action

    @Test func aPendingActionRunsOnce() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingActionStore(directory: directory)
        #expect(store.consume(now: now) == nil)

        try store.post(PendingAction(kind: .quickEntry, prefill: "hello", createdAt: now))
        let action = store.consume(now: now.addingTimeInterval(5))
        #expect(action == PendingAction(kind: .quickEntry, prefill: "hello", createdAt: now))
        #expect(store.consume(now: now.addingTimeInterval(6)) == nil, "the file is gone after it is read")
    }

    @Test func aStaleActionIsIgnoredAndCleared() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingActionStore(directory: directory)
        try store.post(PendingAction(kind: .quickEntry, createdAt: now))
        #expect(store.consume(now: now.addingTimeInterval(PendingAction.timeToLive + 1)) == nil)
        #expect(store.consume(now: now) == nil, "a stale action does not come back")
    }

    @Test func aNewActionReplacesAnOlderOne() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingActionStore(directory: directory)
        try store.post(PendingAction(kind: .quickEntry, prefill: "old", createdAt: now))
        try store.post(PendingAction(kind: .quickEntry, prefill: "new", createdAt: now.addingTimeInterval(1)))
        #expect(store.consume(now: now.addingTimeInterval(2))?.prefill == "new")
    }

    @Test func freshnessHasBounds() {
        let action = PendingAction(kind: .quickEntry, createdAt: now)
        #expect(action.isFresh(at: now))
        #expect(action.isFresh(at: now.addingTimeInterval(PendingAction.timeToLive)))
        #expect(!action.isFresh(at: now.addingTimeInterval(PendingAction.timeToLive + 1)))
        #expect(!action.isFresh(at: now.addingTimeInterval(-1)), "a clock that moved back does not revive an action")
    }
}
