import Foundation
import HermesKit
import Testing

private let chats = [
    SpotlightChat(id: "s1", title: "Backup cron fix", detail: "14:05"),
    SpotlightChat(id: "s2", title: "Release notes", detail: "Yesterday"),
]
private let bots = [SpotlightBot(name: "ops", title: "Ops bot")]

@Suite struct SpotlightPlannerTests {
    @Test func theFirstRunIndexesEverything() {
        let plan = SpotlightPlanner.plan(chats: chats, bots: bots, indexed: SpotlightIndexState())
        #expect(plan.upserts.map(\.identifier) == ["chat:s1", "chat:s2", "bot:ops"])
        #expect(plan.upserts.map(\.kind) == [.chat, .chat, .bot])
        #expect(plan.upserts.map(\.title) == ["Backup cron fix", "Release notes", "Ops bot"])
        #expect(plan.upserts.map(\.detail) == ["14:05", "Yesterday", "Bot"])
        #expect(plan.deletions.isEmpty)
        #expect(plan.upserts.allSatisfy { $0.keywords.contains("simplyHermes") })
    }

    @Test func anUnchangedListSendsNothing() {
        let first = SpotlightPlanner.plan(chats: chats, bots: bots, indexed: SpotlightIndexState())
        let state = SpotlightPlanner.applying(first, to: SpotlightIndexState())
        let second = SpotlightPlanner.plan(chats: chats, bots: bots, indexed: state)
        #expect(second.isEmpty)
    }

    @Test func aRenamedChatReplacesItsEntry() {
        let state = SpotlightPlanner.applying(
            SpotlightPlanner.plan(chats: chats, bots: bots, indexed: SpotlightIndexState()), to: SpotlightIndexState())
        var renamed = chats
        renamed[0].title = "Backup cron fix (done)"
        let plan = SpotlightPlanner.plan(chats: renamed, bots: bots, indexed: state)
        #expect(plan.upserts.map(\.identifier) == ["chat:s1"] && plan.upserts.first?.title == "Backup cron fix (done)")
        #expect(plan.deletions.isEmpty, "the stable id means the old entry is replaced, not left behind")
    }

    @Test func aTimeLabelChangeIsAnUpdateToo() {
        let state = SpotlightPlanner.applying(
            SpotlightPlanner.plan(chats: chats, bots: [], indexed: SpotlightIndexState()), to: SpotlightIndexState())
        var later = chats
        later[1].detail = "Monday"
        #expect(SpotlightPlanner.plan(chats: later, bots: [], indexed: state).upserts.map(\.identifier) == ["chat:s2"])
    }

    @Test func deletedChatsAndBotsAreRemoved() {
        let state = SpotlightPlanner.applying(
            SpotlightPlanner.plan(chats: chats, bots: bots, indexed: SpotlightIndexState()), to: SpotlightIndexState())
        let plan = SpotlightPlanner.plan(chats: [chats[1]], bots: [], indexed: state)
        #expect(plan.upserts.isEmpty)
        #expect(plan.deletions == ["bot:ops", "chat:s1"], "sorted, so the result is the same on every run")

        let after = SpotlightPlanner.applying(plan, to: state)
        #expect(after.fingerprints.keys.sorted() == ["chat:s2"])
        #expect(SpotlightPlanner.plan(chats: [chats[1]], bots: [], indexed: after).isEmpty)
    }

    @Test func entriesWithNothingToSearchForAreSkipped() {
        let input = [
            SpotlightChat(id: "a", title: "  "),
            SpotlightChat(id: "b", title: "Untitled chat"),
            SpotlightChat(id: "c", title: "NEW CHAT"),
            SpotlightChat(id: "", title: "No id"),
            SpotlightChat(id: "d", title: "Kept"),
            SpotlightChat(id: "d", title: "Kept again"),
        ]
        let plan = SpotlightPlanner.plan(
            chats: input, bots: [SpotlightBot(name: "", title: "")], indexed: SpotlightIndexState())
        #expect(plan.upserts.map(\.identifier) == ["chat:d"] && plan.upserts.first?.title == "Kept")
    }

    @Test func aStalePlaceholderEntryIsRemovedOnceTheChatIsRenamedBack() {
        var state = SpotlightIndexState()
        state.fingerprints["chat:x"] = "chat|Old title||"
        let plan = SpotlightPlanner.plan(
            chats: [SpotlightChat(id: "x", title: "Untitled chat")], bots: [], indexed: state)
        #expect(plan.deletions == ["chat:x"] && plan.upserts.isEmpty)
    }

    @Test func titlesAreOneShortLine() {
        let messy = SpotlightChat(id: "m", title: "Line one\n\n  line   two\tend", detail: " \n ")
        let long = SpotlightChat(id: "l", title: String(repeating: "word ", count: 100))
        let plan = SpotlightPlanner.plan(chats: [messy, long], bots: [], indexed: SpotlightIndexState())
        #expect(plan.upserts[0].title == "Line one line two end")
        #expect(plan.upserts[0].detail == nil, "a blank label is dropped")
        #expect(plan.upserts[1].title.count == SpotlightPlanner.maxTitleLength && plan.upserts[1].title.hasSuffix("…"))
    }

    @Test func entriesHoldOnlyTheTitleTheLabelAndFixedKeywords() {
        let input = [SpotlightChat(id: "s1", title: "Deploy script", detail: "Today")]
        let item = SpotlightPlanner.plan(chats: input, bots: [], indexed: SpotlightIndexState()).upserts[0]
        let allowed: Set<String> = ["chat:s1", "Deploy script", "Today", "simplyHermes", "Hermes", "chat"]
        let strings = [item.identifier, item.title, item.detail ?? "", item.domain] + item.keywords
        #expect(Set(strings).isSubset(of: allowed), "\(strings)")
    }

    @Test func onlyTheNewestChatsAreIndexed() {
        let many = (1...(SpotlightPlanner.maxChats + 20)).map { SpotlightChat(id: "s\($0)", title: "Chat \($0)") }
        let plan = SpotlightPlanner.plan(chats: many, bots: [], indexed: SpotlightIndexState())
        #expect(plan.upserts.count == SpotlightPlanner.maxChats)
        #expect(plan.upserts.first?.identifier == "chat:s1")
        #expect(plan.upserts.last?.identifier == "chat:s\(SpotlightPlanner.maxChats)")
    }

    @Test func aBotKeepsItsProfileNameAsAKeyword() {
        let item = SpotlightPlanner.plan(chats: [], bots: bots, indexed: SpotlightIndexState()).upserts[0]
        #expect(item.keywords.contains("ops") && item.keywords.contains("bot"))
        let plain = SpotlightPlanner.plan(
            chats: [], bots: [SpotlightBot(name: "ops", title: "")], indexed: SpotlightIndexState())
        #expect(plain.upserts[0].title == "ops")
    }

    @Test func resultsOpenTheRightThing() {
        #expect(SpotlightPlanner.target(of: SpotlightPlanner.identifier(chat: "s1")) == .chat("s1"))
        #expect(SpotlightPlanner.target(of: SpotlightPlanner.identifier(bot: "ops")) == .bot("ops"))
        #expect(SpotlightPlanner.target(of: "chat:") == nil)
        #expect(SpotlightPlanner.target(of: "bot:") == nil)
        #expect(SpotlightPlanner.target(of: "other:s1") == nil)
        #expect(SpotlightPlanner.target(of: "") == nil)
    }

    @Test func theIndexStateSurvivesRestarts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpotlightIndexState.store(directory: directory)
        #expect(store.load() == nil)
        let plan = SpotlightPlanner.plan(chats: chats, bots: bots, indexed: SpotlightIndexState())
        let state = SpotlightPlanner.applying(plan, to: SpotlightIndexState())
        try store.save(state)
        let reloaded = try #require(store.load())
        #expect(SpotlightPlanner.plan(chats: chats, bots: bots, indexed: reloaded).isEmpty)
    }

    @Test func anOlderStateIsNotCurrentAndANewOneIs() throws {
        #expect(SpotlightIndexState().isCurrent)
        let saved = Data(#"{"fingerprints":{"chat:c1":"chat|Deploy|"}}"#.utf8)
        let older = try JSONDecoder().decode(SpotlightIndexState.self, from: saved)
        #expect(!older.isCurrent)
    }
}
