import Foundation
import GRDB
import Testing

@testable import HermesKit

/// A reply that never arrived is recoverable: each unanswered question stays listed, survives a reopen, and retry adds
/// exactly one reply to the question it names.
struct LocalChatRetryTests {
    private let gemma = ModelIdentity.downloaded(id: "gemma-3-1b-4bit", displayName: "Gemma 3 1B")

    private func answerer(_ outcome: ScriptedExecutor.Outcome, as model: ModelIdentity = .apple) -> FixedModelAnswerer {
        FixedModelAnswerer(identity: model, executor: ScriptedExecutor(outcome))
    }

    // An earlier question whose reply failed stays retryable after a later question is answered.
    @Test func anEarlierFailedQuestionRemainsRetryableAfterALaterAnswer() async throws {
        let store = try HermesCache().localChats
        let slot = AnswererSlot(answerer(.throwing))
        let controller = await LocalChatController(
            store: store, answerer: { slot.get() }, chatID: UUID(), now: { localChatStart })

        await controller.send("first question")
        slot.set(answerer(.reply("second answer")))
        await controller.send("second question")

        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.text) == ["first question", "second question", "second answer"])
        #expect(snapshot.unansweredIDs == [1])
        #expect(snapshot.needsReply)
    }

    // Retry on the earlier question: one reply that names it, still two user rows, nothing left unanswered.
    @Test func retryOfAnEarlierQuestionAddsOneReplyToThatQuestion() async throws {
        let store = try HermesCache().localChats
        let slot = AnswererSlot(answerer(.throwing))
        let id = UUID()
        let controller = await LocalChatController(
            store: store, answerer: { slot.get() }, chatID: id, now: { localChatStart })
        await controller.send("first question")
        slot.set(answerer(.reply("second answer")))
        await controller.send("second question")

        slot.set(answerer(.reply("first answer"), as: gemma))
        await controller.retry(messageID: 1)

        let stored = try await store.messages(inChat: id)
        let users = stored.filter { $0.author == .user }
        #expect(users.map(\.text) == ["first question", "second question"])
        let replies = stored.filter { if case .assistant = $0.author { true } else { false } }
        #expect(replies.map(\.author).contains(.assistant(answeredBy: gemma, inReplyTo: 1)))
        #expect(replies.count == 2)
        #expect(await controller.snapshot.unansweredIDs.isEmpty)
    }

    // Reopen before the retry: the unanswered question is found from the stored rows, not from memory.
    @Test func aReopenedChatListsTheEarlierUnansweredQuestion() async throws {
        let url = try temporaryDatabaseURL()
        let id = UUID()
        do {
            let store = try HermesCache(url: url).localChats
            _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
            _ = try await store.appendUserMessage("first question", toChat: id, at: localChatStart)
            _ = try await store.appendUserMessage("second question", toChat: id, at: localChatStart)
            _ = try await store.appendReply(
                LocalReply(text: "second answer", answeredBy: .apple, inReplyTo: 2), toChat: id, at: localChatStart)
        }
        let reopened = GRDBLocalChatStore(database: try DatabaseQueue(path: url.path))
        let controller = await LocalChatController(
            store: reopened, answerer: { answerer(.reply("unused")) }, chatID: id, now: { localChatStart })
        #expect(await controller.snapshot.unansweredIDs == [1])
    }

    // A retry whose model throws adds no assistant row, and the question stays unanswered.
    @Test func aRetryThatFailsAddsNoAssistantRow() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
        _ = try await store.appendUserMessage("Q", toChat: id, at: localChatStart)
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.throwing) }, chatID: id, now: { localChatStart })

        await controller.retry(messageID: 1)

        #expect(try await store.messages(inChat: id).map(\.author) == [.user])
        #expect(await controller.snapshot.failure == .modelFailed)
        #expect(await controller.snapshot.unansweredIDs == [1])
    }

    // A blank retry is treated like a throw: no row, still unanswered.
    @Test func aBlankRetryAddsNoAssistantRow() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
        _ = try await store.appendUserMessage("Q", toChat: id, at: localChatStart)
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.blank) }, chatID: id, now: { localChatStart })

        await controller.retry(messageID: 1)

        #expect(try await store.messages(inChat: id).map(\.author) == [.user])
        #expect(await controller.snapshot.unansweredIDs == [1])
    }

    // Ids that are not unanswered questions are ignored: an answered question, and an id that does not exist.
    @Test func retryIgnoresIdsThatAreNotUnansweredQuestions() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.reply("answer")) }, chatID: id, now: { localChatStart })
        await controller.send("question")
        await controller.retry(messageID: 1)
        await controller.retry(messageID: 99)

        let stored = try await store.messages(inChat: id)
        #expect(stored.count == 2)
        #expect(await controller.snapshot.unansweredIDs.isEmpty)
    }

    // m1: a row whose id is not a UUID is skipped, so no chat gets a made-up id.
    @Test func aChatRowWithABrokenIdIsSkippedNotRenamed() async throws {
        let url = try temporaryDatabaseURL()
        let store = try HermesCache(url: url).localChats
        let good = UUID()
        _ = try await store.createChat(id: good, title: "Good", at: localChatStart)
        let raw = try DatabaseQueue(path: url.path)
        try await raw.write { handle in
            try handle.execute(
                sql: """
                    INSERT INTO local_chats (chat_id, title, created_at, updated_at)
                    VALUES ('not-a-uuid', 'Broken', ?, ?)
                    """,
                arguments: [localChatStart.timeIntervalSince1970, localChatStart.timeIntervalSince1970])
        }
        #expect(try await store.chats(limit: 10).map(\.id) == [good])
    }
}
