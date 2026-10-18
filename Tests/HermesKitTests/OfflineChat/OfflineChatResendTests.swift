import Foundation
import Testing

@testable import HermesKit

struct OfflineChatResendTests {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func chat(resolution: OfflineChat.Resolution? = nil) -> OfflineChat {
        OfflineChat(
            id: "chat-1", sessionID: "s1", title: "t", createdAt: when, updatedAt: when, resolution: resolution)
    }

    private func message(_ id: Int, _ role: OfflineChatMessage.Role, _ text: String) -> OfflineChatMessage {
        OfflineChatMessage(chatID: "chat-1", id: id, role: role, text: text, createdAt: when)
    }

    private func offer(
        _ messages: [OfflineChatMessage], chat: OfflineChat? = nil, server: ServerReachability = .reachable
    ) -> SendToHermesOffer? {
        SendToHermes.offer(chat: chat ?? self.chat(), messages: messages, server: server)
    }

    @Test func theLastPromptIsOfferedOnceTheServerIsBack() {
        let messages = [message(1, .user, "first"), message(2, .assistant, "reply"), message(3, .user, "second")]
        #expect(offer(messages) == SendToHermesOffer(chatID: "chat-1", messageID: 3, prompt: "second"))
    }

    @Test func thePromptStaysTheOfferedOneAfterTheModelAnswered() {
        let messages = [
            message(1, .user, "first"), message(2, .assistant, "reply"), message(3, .user, "second"),
            message(4, .assistant, "another reply"),
        ]
        #expect(offer(messages)?.messageID == 3)
        #expect(offer(messages)?.prompt == "second")
    }

    @Test func onlyThePromptTravelsNeverTheModelsReply() {
        let messages = [message(1, .user, "question"), message(2, .assistant, "answer from the phone")]
        let found = offer(messages)
        #expect(found?.prompt == "question")
        #expect(found?.prompt.contains("answer from the phone") == false)
    }

    @Test func anUnansweredPromptIsStillOffered() {
        #expect(offer([message(1, .user, "no reply came")])?.prompt == "no reply came")
    }

    @Test func nothingIsOfferedUntilTheServerIsReachable() {
        let messages = [message(1, .user, "hello")]
        #expect(offer(messages, server: .unreachable) == nil)
        #expect(offer(messages, server: .unknown) == nil)
        #expect(offer(messages, server: .needsAttention) == nil)
        #expect(offer(messages, server: .reachable) != nil)
    }

    @Test func nothingIsOfferedForAClosedChat() {
        let messages = [message(1, .user, "hello")]
        #expect(offer(messages, chat: chat(resolution: .sent)) == nil)
        #expect(offer(messages, chat: chat(resolution: .dismissed)) == nil)
    }

    @Test func nothingIsOfferedWithoutAChatOrAPrompt() {
        #expect(SendToHermes.offer(chat: nil, messages: [message(1, .user, "hello")], server: .reachable) == nil)
        #expect(offer([]) == nil)
        #expect(offer([message(1, .assistant, "I only talk back")]) == nil)
    }

    @Test func aBlankPromptIsNotOffered() {
        #expect(offer([message(1, .user, "   \n ")]) == nil)
    }

    @Test func thePromptIsTrimmed() {
        #expect(offer([message(1, .user, "  hello there \n")])?.prompt == "hello there")
    }

    @Test func messagesOfAnotherChatAreIgnored() {
        let stray = OfflineChatMessage(chatID: "other", id: 9, role: .user, text: "not mine", createdAt: when)
        #expect(offer([message(1, .user, "mine"), stray])?.prompt == "mine")
    }

    // MARK: - One send at a time

    private let tapped = SendToHermesOffer(chatID: "chat-1", messageID: 3, prompt: "second")

    @Test func nothingIsSendingBeforeTheFirstTap() {
        let progress = SendToHermesProgress()
        #expect(progress.sending == nil)
        #expect(!progress.isSending(tapped))
        #expect(!progress.isSending(nil))
    }

    @Test func onlyTheFirstTapOnAnOfferSends() {
        var progress = SendToHermesProgress()
        let first = progress.begin(tapped)
        let second = progress.begin(tapped)
        let third = progress.begin(tapped)
        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(progress.isSending(tapped))
    }

    @Test func anOfferWhoseSendFailedCanBeTappedAgain() {
        var progress = SendToHermesProgress()
        let first = progress.begin(tapped)
        progress.fail()
        #expect(first)
        #expect(!progress.isSending(tapped))
        let again = progress.begin(tapped)
        #expect(again)
    }

    @Test func theButtonComesBackOnceTheOfferIsGone() {
        var progress = SendToHermesProgress()
        let sent = progress.begin(tapped)
        #expect(sent)
        // The offline chat was closed, so the offer is gone from the screen.
        #expect(!progress.isSending(nil))
        // The next offline chat offers another prompt, and that one can be sent.
        let next = SendToHermesOffer(chatID: "chat-2", messageID: 1, prompt: "later")
        #expect(!progress.isSending(next))
        let nextSent = progress.begin(next)
        #expect(nextSent)
        #expect(progress.isSending(next))
        #expect(!progress.isSending(tapped))
    }

    // MARK: - With the chat controller and a store

    @Test func theOfferGoesAwayOnceTheUserAnswersIt() async throws {
        let store = try HermesCache().offlineChats
        let controller = await OfflineChatController(
            store: store, executor: { OfflineReplyModel() }, connection: "x", sessionID: "s1")
        await controller.send("what is a monad")
        let before = await controller.snapshot
        #expect(
            SendToHermes.offer(chat: before.chat, messages: before.messages, server: .reachable)?.prompt
                == "what is a monad")

        await controller.resolve(.sent)
        let after = await controller.snapshot
        #expect(SendToHermes.offer(chat: after.chat, messages: after.messages, server: .reachable) == nil)
        // A new session of the app does not bring the offer back.
        let reopened = await OfflineChatController(
            store: store, executor: { OfflineReplyModel() }, connection: "x", sessionID: "s1")
        let again = await reopened.snapshot
        #expect(SendToHermes.offer(chat: again.chat, messages: again.messages, server: .reachable) == nil)
    }

    @Test func theOfferComesBackAfterARelaunchUntilTheUserAnswersIt() async throws {
        let store = try HermesCache().offlineChats
        let first = await OfflineChatController(
            store: store, executor: { OfflineReplyModel() }, connection: "x", sessionID: "s1")
        await first.send("remember me")
        let reopened = await OfflineChatController(
            store: store, executor: { OfflineReplyModel() }, connection: "x", sessionID: "s1")
        let snapshot = await reopened.snapshot
        #expect(
            SendToHermes.offer(chat: snapshot.chat, messages: snapshot.messages, server: .reachable)?.prompt
                == "remember me")
    }
}

/// Answers every prompt with a fixed line.
struct OfflineReplyModel: LocalModelExecutor {
    var availability: LocalModelAvailability = .available

    func respond(instructions: String, prompt: String) async throws -> String { "an offline answer" }
}
