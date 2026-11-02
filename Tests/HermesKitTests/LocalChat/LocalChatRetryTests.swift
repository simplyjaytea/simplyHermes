import Foundation
import GRDB
import Testing

@testable import HermesKit

/// A reply that never arrived is recoverable: it shows as unanswered after a reopen, and retry adds exactly one reply.
struct LocalChatRetryTests {
    private let gemma = ModelIdentity.downloaded(id: "gemma-3-1b-4bit", displayName: "Gemma 3 1B")

    private func answerer(_ outcome: ScriptedExecutor.Outcome, as model: ModelIdentity = .apple) -> FixedModelAnswerer {
        FixedModelAnswerer(identity: model, executor: ScriptedExecutor(outcome))
    }

    // (a) The app was killed after the question was saved and before the reply: reopening shows it unanswered.
    @Test func aReopenedChatWhoseLastMessageHasNoReplyNeedsOne() async throws {
        let url = try temporaryDatabaseURL()
        let id = UUID()
        do {
            let store = try HermesCache(url: url).localChats
            _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
            _ = try await store.appendUserMessage("Q", toChat: id, at: localChatStart)
        }
        let reopened = GRDBLocalChatStore(database: try DatabaseQueue(path: url.path))
        let controller = await LocalChatController(
            store: reopened, answerer: { answerer(.reply("unused")) }, chatID: id, now: { localChatStart })
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.author) == [.user])
        #expect(snapshot.needsReply)
    }

    // (b) Retry answers the waiting question: one reply with its model, and still one user row.
    @Test func retryAddsExactlyOneReplyAndNoUserRow() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
        _ = try await store.appendUserMessage("Q", toChat: id, at: localChatStart)
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.reply("the answer"), as: gemma) }, chatID: id, now: { localChatStart })

        await controller.retry()

        let stored = try await store.messages(inChat: id)
        #expect(stored.map(\.author) == [.user, .assistant(answeredBy: gemma)])
        #expect(stored.map(\.text) == ["Q", "the answer"])
        #expect(await controller.snapshot.needsReply == false)
        #expect(await controller.snapshot.failure == nil)
    }

    // (c) Retry while the model throws: still no assistant row, and the question stays unanswered.
    @Test func aRetryThatFailsAddsNoAssistantRow() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        _ = try await store.createChat(id: id, title: "Q", at: localChatStart)
        _ = try await store.appendUserMessage("Q", toChat: id, at: localChatStart)
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.throwing) }, chatID: id, now: { localChatStart })

        await controller.retry()

        #expect(try await store.messages(inChat: id).map(\.author) == [.user])
        #expect(await controller.snapshot.failure == .modelFailed)
        #expect(await controller.snapshot.needsReply)
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
                sql:
                    "INSERT INTO local_chats (chat_id, title, created_at, updated_at) VALUES ('not-a-uuid', 'Broken', ?, ?)",
                arguments: [localChatStart.timeIntervalSince1970, localChatStart.timeIntervalSince1970])
        }
        let listed = try await store.chats(limit: 10)
        #expect(listed.map(\.id) == [good])
        #expect(listed.map(\.id).allSatisfy { $0 == good })
    }
}
