import Foundation
import HermesKit
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct IntentMappingTests {
    // MARK: Parameters to requests

    @Test func askKeepsTheTextAndTheChosenChat() throws {
        #expect(
            try IntentMapping.ask(text: "  What is new?  ", chatID: "s1") == .ask(text: "What is new?", chatID: "s1"))
        #expect(try IntentMapping.ask(text: "Hi", chatID: nil) == .ask(text: "Hi", chatID: nil))
        #expect(
            try IntentMapping.ask(text: "Hi", chatID: "  ") == .ask(text: "Hi", chatID: nil),
            "a blank chat means the last one")
    }

    @Test func askNeedsSomethingToSend() {
        #expect(throws: IntentMappingError.emptyMessage) { try IntentMapping.ask(text: " \n ", chatID: "s1") }
        #expect(IntentMappingError.emptyMessage.dialog == "There is nothing to send.")
        #expect(IntentMappingError.dialog(for: IntentMappingError.missingBot) == "Choose a bot first.")
        #expect(IntentMappingError.dialog(for: CancellationError()) == IntentOutcome.needsApp.dialog)
    }

    @Test func longTextIsCutToTheIntentLimit() throws {
        let request = try IntentMapping.ask(
            text: String(repeating: "a", count: IntentMapping.maxMessageCharacters + 50), chatID: nil)
        guard case .ask(let text, _) = request else {
            Issue.record("expected an ask request")
            return
        }
        #expect(text.count == IntentMapping.maxMessageCharacters)
    }

    @Test func askBotNeedsABotAndText() throws {
        #expect(try IntentMapping.askBot(bot: " ops ", text: " status? ") == .askBot(bot: "ops", text: "status?"))
        #expect(throws: IntentMappingError.missingBot) { try IntentMapping.askBot(bot: "  ", text: "hi") }
        #expect(throws: IntentMappingError.emptyMessage) { try IntentMapping.askBot(bot: "ops", text: "") }
    }

    @Test func aBlankFirstMessageJustOpensANewChat() {
        #expect(IntentMapping.newChat(text: nil) == .newChat(text: nil))
        #expect(IntentMapping.newChat(text: "  ") == .newChat(text: nil))
        #expect(IntentMapping.newChat(text: " Plan my day ") == .newChat(text: "Plan my day"))
    }

    @Test func quickEntryKeepsOnlyRealPrefill() {
        #expect(IntentMapping.quickEntry(prefill: nil) == .openQuickEntry(prefill: nil))
        #expect(IntentMapping.quickEntry(prefill: " \n") == .openQuickEntry(prefill: nil))
        #expect(IntentMapping.quickEntry(prefill: "hello") == .openQuickEntry(prefill: "hello"))
    }

    // MARK: Requests to messages

    @Test func requestsThatSendBecomeMessages() {
        let toChat = IntentMapping.message(for: .ask(text: "hi", chatID: "s1"), id: "m1", now: now)
        #expect(toChat == OutboundMessage(id: "m1", text: "hi", target: .chat("s1"), createdAt: now))
        let toLast = IntentMapping.message(for: .ask(text: "hi", chatID: nil), id: "m2", now: now)
        #expect(toLast?.target == .lastUsed)
        let toBot = IntentMapping.message(for: .askBot(bot: "ops", text: "status?"), id: "m3", now: now)
        #expect(toBot?.target == .newChat && toBot?.text == "status?")
        let first = IntentMapping.message(for: .newChat(text: "first"), id: "m4", now: now)
        #expect(first?.target == .newChat && first?.text == "first")
    }

    @Test func requestsThatOnlyActMakeNoMessage() {
        let requests: [IntentRequest] = [.newChat(text: nil), .stopAll, .approvePending, .openQuickEntry(prefill: "x")]
        for request in requests {
            #expect(IntentMapping.message(for: request, now: now) == nil, "\(request)")
        }
    }

    // MARK: Approve pending

    @Test func approvePendingActsOnlyWhenThereIsNoDoubt() {
        let one = PendingApprovalRef(sessionID: "s1", chatTitle: "Deploy", command: "make deploy")
        let two = PendingApprovalRef(sessionID: "s2", chatTitle: "Backup", command: "rm -rf /tmp/x")
        #expect(ApprovalPicker.pick([]) == .nothing)
        #expect(ApprovalPicker.pick([one]) == .approve(one))
        #expect(ApprovalPicker.pick([one, two]) == .several(count: 2))
    }

    // MARK: What Siri says

    @Test func outcomesReadAsCalmSentences() {
        #expect(IntentOutcome.queued(chatTitle: "Backup cron fix").dialog == "Sending to Backup cron fix.")
        #expect(IntentOutcome.queued(chatTitle: nil).dialog == "Sending to a new chat.")
        #expect(IntentOutcome.afterStopping(0) == .nothingRunning)
        #expect(IntentOutcome.afterStopping(1).dialog == "Stopped 1 turn.")
        #expect(IntentOutcome.afterStopping(3).dialog == "Stopped 3 turns.")
        #expect(IntentOutcome.nothingToApprove.dialog == "Nothing is waiting for approval.")
        #expect(IntentOutcome.severalToApprove(count: 2).dialog.hasPrefix("2 approvals are waiting."))
        #expect(IntentOutcome.unknownBot("ops").dialog == "I could not find a bot called ops.")
        #expect(IntentOutcome.needsApp.dialog == "Open simplyHermes to continue.")
        #expect(IntentOutcome.notConnected.dialog.hasPrefix("simplyHermes is not connected"))
        #expect(IntentOutcome.askedBot(name: "Ops bot").dialog == "Asking Ops bot.")
        #expect(IntentOutcome.approved(command: "make deploy").dialog == "Approved: make deploy")
        let long = IntentOutcome.approved(command: String(repeating: "x", count: 500)).dialog
        #expect(long.count < 100, "a long command is cut before it is spoken")
    }
}

@Suite struct OutboundPlannerTests {
    private func message(_ target: OutboundTarget, age: TimeInterval = 0) -> OutboundMessage {
        OutboundMessage(id: "m", text: "hi", target: target, createdAt: now.addingTimeInterval(-age))
    }

    // MARK: Picking the chat

    @Test func aNewChatTargetNeedsNoWaiting() {
        let step = OutboundPlanner.resolve(message(.newChat), bound: nil, knownChatIDs: [], lastUsedID: "s1", now: now)
        #expect(step == .createChat)
    }

    @Test func aKnownChatIsUsedAtOnce() {
        let known: Set<String> = ["s1", "s2"]
        #expect(
            OutboundPlanner.resolve(message(.chat("s2")), bound: nil, knownChatIDs: known, lastUsedID: nil, now: now)
                == .chat("s2"))
        #expect(
            OutboundPlanner.resolve(message(.lastUsed), bound: nil, knownChatIDs: known, lastUsedID: "s1", now: now)
                == .chat("s1"))
    }

    @Test func aChatNotListedYetIsWaitedFor() {
        let early = message(.chat("s9"), age: OutboundPlanner.listPatience - 1)
        #expect(OutboundPlanner.resolve(early, bound: nil, knownChatIDs: ["s1"], lastUsedID: nil, now: now) == .wait)
        let late = message(.lastUsed, age: OutboundPlanner.listPatience + 1)
        #expect(
            OutboundPlanner.resolve(late, bound: nil, knownChatIDs: ["s1"], lastUsedID: "s9", now: now) == .createChat)
    }

    @Test func noLastChatMeansANewChat() {
        let step = OutboundPlanner.resolve(
            message(.lastUsed), bound: nil, knownChatIDs: ["s1"], lastUsedID: nil, now: now)
        #expect(step == .createChat)
    }

    @Test func aChatCreatedForAMessageStaysItsChat() {
        let step = OutboundPlanner.resolve(
            message(.newChat), bound: "new-3", knownChatIDs: [], lastUsedID: nil, now: now)
        #expect(step == .chat("new-3"))
    }

    // MARK: Delivering

    @Test func placeholderChatsTakeTheMessageAtOnce() {
        let step = OutboundPlanner.step(for: message(.newChat), isLive: false, readiness: .loading, now: now)
        #expect(step == .send)
    }

    @Test func aServerChatTakesTheMessageOnceItIsReady() {
        #expect(OutboundPlanner.step(for: message(.lastUsed), isLive: true, readiness: .ready, now: now) == .send)
        #expect(OutboundPlanner.step(for: message(.lastUsed), isLive: true, readiness: .loading, now: now) == .wait)
    }

    @Test func aChatThatDoesNotConnectKeepsTheMessageAsADraft() {
        let late = message(.lastUsed, age: OutboundPlanner.connectPatience + 1)
        #expect(OutboundPlanner.step(for: late, isLive: true, readiness: .loading, now: now) == .saveAsDraft)
        #expect(
            OutboundPlanner.step(for: message(.lastUsed), isLive: true, readiness: .failed, now: now) == .saveAsDraft)
    }

    @Test func draftsAreAddedBelowWhatTheUserTyped() {
        #expect(OutboundPlanner.draft(existing: "", adding: "shared") == "shared")
        #expect(OutboundPlanner.draft(existing: "  \n", adding: "shared") == "shared")
        #expect(OutboundPlanner.draft(existing: "my note", adding: " shared ") == "my note\n\nshared")
        #expect(OutboundPlanner.draft(existing: "my note", adding: " ") == "my note")
    }

    // MARK: Quick Entry

    @Test func quickEntryFollowsUpInTheLastChatOrStartsANewOne() {
        let last = RecentChat(id: "s1", title: "Backup cron fix", subtitle: "14:05")
        let follow = QuickEntryPolicy.destination(lastChat: last)
        #expect(follow.target == .chat("s1") && follow.label == "Sends to Backup cron fix")
        let fresh = QuickEntryPolicy.destination(lastChat: nil)
        #expect(fresh.target == .newChat && fresh.label == "Sends to a new chat")
        #expect(
            QuickEntryPolicy.destination(lastChat: RecentChat(id: "s2", title: "")).label == "Sends to Untitled chat")
    }
}

@Suite struct IntegrationBotRosterTests {
    private func profiles() throws -> [HermesProfile] {
        let json = """
            [{"name":"default","is_default":true},
             {"name":"ops","display_name":"Ops bot"},
             {"name":"research","display_name":""},
             {"name":"zoë","display_name":"Zoë"}]
            """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([HermesProfile].self, from: Data(json.utf8))
    }

    @Test func theDefaultProfileIsNotABot() throws {
        let roster = IntegrationBotRoster(profiles: try profiles(), updatedAt: now)
        #expect(roster.bots.map(\.name) == ["ops", "research", "zoë"])
        #expect(
            roster.bots.map(\.title) == ["Ops bot", "research", "Zoë"], "an empty display name falls back to the name")
    }

    @Test func spokenNamesMatchLoosely() throws {
        let roster = IntegrationBotRoster(profiles: try profiles(), updatedAt: now)
        #expect(roster.bot(named: "ops")?.name == "ops")
        #expect(roster.bot(named: "  OPS BOT ")?.name == "ops")
        #expect(roster.bot(named: "zoe")?.name == "zoë", "accents do not matter")
        #expect(roster.bot(named: "default") == nil)
        #expect(roster.bot(named: "") == nil)
        #expect(roster.bot(named: "nobody") == nil)
    }

    @Test func theRosterRoundTripsThroughItsFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IntegrationBotRoster.store(directory: directory)
        #expect(store.load() == nil)
        let roster = IntegrationBotRoster(profiles: try profiles(), updatedAt: now)
        try store.save(roster)
        #expect(store.load() == roster)
        #expect(
            roster.hasSameContent(as: IntegrationBotRoster(bots: roster.bots, updatedAt: now.addingTimeInterval(9))))
        #expect(!roster.hasSameContent(as: IntegrationBotRoster(bots: [], updatedAt: now)))
    }
}
