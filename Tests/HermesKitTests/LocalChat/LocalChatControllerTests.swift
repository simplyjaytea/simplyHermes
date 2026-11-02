import Foundation
import GRDB
import Testing

@testable import HermesKit

struct LocalChatControllerTests {
    private let gemma = ModelIdentity.downloaded(id: "gemma-3-1b-4bit", displayName: "Gemma 3 1B")

    private func answerer(_ outcome: ScriptedExecutor.Outcome, as model: ModelIdentity = .apple) -> FixedModelAnswerer {
        FixedModelAnswerer(identity: model, executor: ScriptedExecutor(outcome))
    }

    // AT-2: a local chat runs send -> reply -> reopen the store -> send, with no server, no gateway and no transport.
    // The controller takes only a store and an answerer, so nothing it holds can reach the network.
    @Test func sendReplyReopenSendNeverNeedsAServer() async throws {
        let url = try temporaryDatabaseURL()
        let slot = AnswererSlot(answerer(.reply("first reply")))
        let id = UUID()
        do {
            let store = try HermesCache(url: url).localChats
            let controller = await LocalChatController(
                store: store, answerer: { slot.get() }, chatID: id, now: { localChatStart })
            await controller.send("first question")
            let snapshot = await controller.snapshot
            #expect(snapshot.messages.map(\.text) == ["first question", "first reply"])
            #expect(snapshot.messages.last?.author == .assistant(answeredBy: .apple))
            #expect(snapshot.failure == nil)
        }

        // Relaunch: a new queue on the same file, and a new controller that opens the chat again.
        let reopened = GRDBLocalChatStore(database: try DatabaseQueue(path: url.path))
        slot.set(answerer(.reply("second reply"), as: gemma))
        let controller = await LocalChatController(
            store: reopened, answerer: { slot.get() }, chatID: id, now: { localChatStart })
        #expect(await controller.snapshot.messages.count == 2)
        await controller.send("second question")

        let messages = try await reopened.messages(inChat: id)
        #expect(messages.map(\.text) == ["first question", "first reply", "second question", "second reply"])
        #expect(messages[3].author == .assistant(answeredBy: gemma))
    }

    // AT-5b: each saved reply names the executor that produced it, and the next reply names the next one.
    @Test func eachSavedReplyKeepsTheModelThatAnsweredIt() async throws {
        let store = try HermesCache().localChats
        let slot = AnswererSlot(answerer(.reply("from A"), as: .apple))
        let controller = await LocalChatController(
            store: store, answerer: { slot.get() }, chatID: UUID(), now: { localChatStart })

        await controller.send("one")
        slot.set(answerer(.reply("from B"), as: gemma))
        await controller.send("two")

        let replies = await controller.snapshot.messages.filter { $0.author != .user }
        #expect(replies.map(\.text) == ["from A", "from B"])
        #expect(replies.map(\.author) == [.assistant(answeredBy: .apple), .assistant(answeredBy: gemma)])
        let chatID = try #require(await controller.snapshot.chat?.id)
        let stored = try await store.messages(inChat: chatID).filter { $0.author != .user }
        #expect(stored.map(\.author) == [.assistant(answeredBy: .apple), .assistant(answeredBy: gemma)])
    }

    // Executor throws or returns only whitespace: the question is kept, no assistant row is created, and the failure
    // is reported.
    @Test func aThrowingModelAddsNoAssistantRow() async throws {
        let store = try HermesCache().localChats
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.throwing) }, chatID: UUID(), now: { localChatStart })
        await controller.send("hello?")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.author) == [.user])
        #expect(snapshot.failure == .modelFailed)
        let chatID = try #require(snapshot.chat?.id)
        #expect(try await store.messages(inChat: chatID).map(\.author) == [.user])
    }

    @Test func aWhitespaceOnlyReplyAddsNoAssistantRow() async throws {
        let store = try HermesCache().localChats
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.blank) }, chatID: UUID(), now: { localChatStart })
        await controller.send("hello?")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.author) == [.user])
        #expect(snapshot.failure == .modelFailed)
    }

    @Test func aModelThatCannotAnswerSaysWhyAndAddsNoRow() async throws {
        let store = try HermesCache().localChats
        let unavailable = FixedModelAnswerer(
            identity: .apple, executor: ScriptedExecutor(.reply("never"), availability: .unavailable(.switchedOff)))
        let controller = await LocalChatController(
            store: store, answerer: { unavailable }, chatID: UUID(), now: { localChatStart })
        await controller.send("hello?")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.author) == [.user])
        #expect(snapshot.failure == .unavailable(.switchedOff))
    }

    @Test func blankInputIsIgnoredAndNoChatIsCreated() async throws {
        let store = try HermesCache().localChats
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.reply("unused")) }, chatID: UUID(), now: { localChatStart })
        await controller.send("   \n ")
        #expect(await controller.snapshot.chat == nil)
        #expect(try await store.chats(limit: 10).isEmpty)
    }

    @Test func aNewChatHasNoRowUntilItsFirstMessage() async throws {
        let store = try HermesCache().localChats
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.reply("hi")) }, chatID: UUID(), now: { localChatStart })
        #expect(try await store.chats(limit: 10).isEmpty)
        await controller.send("Plan the trip to Kyoto in spring")
        #expect(try await store.chats(limit: 10).map(\.title) == ["Plan the trip to Kyoto in spring"])
    }

    // Two first messages sent together create the chat once, and both messages are saved.
    @Test func firstMessagesSentTogetherCreateOneChat() async throws {
        let store = try HermesCache().localChats
        let id = UUID()
        let controller = await LocalChatController(
            store: store, answerer: { answerer(.reply("ok")) }, chatID: id, now: { localChatStart })
        async let first = controller.submit("one")
        async let second = controller.submit("two")
        let savedFirst = await first
        let savedSecond = await second
        #expect(savedFirst && savedSecond)
        #expect(try await store.chats(limit: 10).map(\.id) == [id])
        await controller.send("three")
        #expect(try await store.messages(inChat: id).map(\.text).contains("three"))
    }
}
