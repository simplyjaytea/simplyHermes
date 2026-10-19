import Foundation
import Testing

@testable import HermesKit

struct OfflineChatStoreTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func later(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func serverMessage(_ rowID: Int, session: String) throws -> StoredMessage {
        let json = #"{"id":\#(rowID),"sessionId":"\#(session)","role":"user","content":"server message"}"#
        return try JSONDecoder().decode(StoredMessage.self, from: Data(json.utf8))
    }

    // MARK: - Chats

    @Test func openingAChatStartsOneAndFindsItAgain() async throws {
        let store = try HermesCache().offlineChats
        #expect(try await store.currentChat(forSession: "s1", connection: "x") == nil)
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "Hello", at: start)
        #expect(chat.sessionID == "s1")
        #expect(chat.title == "Hello")
        #expect(chat.isOpen)
        #expect(chat.createdAt == start)
        #expect(chat.updatedAt == start)
        let again = try await store.openChat(forSession: "s1", connection: "x", title: "Other", at: later(5))
        #expect(again == chat)
        #expect(try await store.currentChat(forSession: "s1", connection: "x") == chat)
    }

    @Test func serverChatsAndConnectionsKeepTheirOwnChats() async throws {
        let store = try HermesCache().offlineChats
        let first = try await store.openChat(forSession: "s1", connection: "x", title: "A", at: start)
        let second = try await store.openChat(forSession: "s2", connection: "x", title: "B", at: start)
        let third = try await store.openChat(forSession: "s1", connection: "y", title: "C", at: start)
        #expect(Set([first.id, second.id, third.id]).count == 3)
        _ = try await store.append(.user, text: "one", toChat: first.id, connection: "x", at: start)
        #expect(try await store.messages(inChat: first.id, connection: "x").count == 1)
        #expect(try await store.messages(inChat: second.id, connection: "x").isEmpty)
        // The same chat id under another connection is a different (empty) chat.
        #expect(try await store.messages(inChat: first.id, connection: "y").isEmpty)
        #expect(try await store.chats(connection: "x", limit: 10).count == 2)
        #expect(try await store.chats(connection: "y", limit: 10) == [third])
    }

    @Test func titlesComeFromTheFirstLineOfThePrompt() {
        #expect(OfflineChat.title(forPrompt: "  What is a monad?\nAnd why?") == "What is a monad?")
        #expect(OfflineChat.title(forPrompt: "  \n ") == OfflineChat.fallbackTitle)
        let long = String(repeating: "a", count: 200)
        #expect(OfflineChat.title(forPrompt: long).count == LocalHelpers.maxTitleLength)
    }

    // MARK: - Messages

    @Test func messagesRoundTripInOrder() async throws {
        let store = try HermesCache().offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "Math", at: start)
        let question = try await store.append(
            .user, text: "What is 2 + 2?", toChat: chat.id, connection: "x", at: start)
        let answer = try await store.append(.assistant, text: "4", toChat: chat.id, connection: "x", at: later(2))
        #expect(question.id == 1)
        #expect(answer.id == 2)
        #expect(question.chatID == chat.id)
        let stored = try await store.messages(inChat: chat.id, connection: "x")
        #expect(stored == [question, answer])
        #expect(stored.map(\.role) == [.user, .assistant])
        #expect(stored.map(\.text) == ["What is 2 + 2?", "4"])
        #expect(stored.map(\.createdAt) == [start, later(2)])
        #expect(try await store.currentChat(forSession: "s1", connection: "x")?.updatedAt == later(2))
    }

    @Test func textKeepsItsLineBreaksAndSymbols() async throws {
        let store = try HermesCache().offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "t", at: start)
        let text = "line one\n\"quoted\" 'single' \\ backslash 日本語 🙂"
        _ = try await store.append(.user, text: text, toChat: chat.id, connection: "x", at: start)
        #expect(try await store.messages(inChat: chat.id, connection: "x").map(\.text) == [text])
    }

    @Test func aMissingChatTakesNoMessages() async throws {
        let store = try HermesCache().offlineChats
        await #expect(throws: OfflineChatError.chatClosed) {
            try await store.append(.user, text: "hi", toChat: "nope", connection: "x", at: start)
        }
    }

    // MARK: - Closing

    @Test func closingAChatEndsItAndTheNextOneIsNew() async throws {
        let store = try HermesCache().offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "First", at: start)
        _ = try await store.append(.user, text: "hello", toChat: chat.id, connection: "x", at: start)
        try await store.resolve(chat: chat.id, connection: "x", as: .sent, at: later(10))

        #expect(try await store.currentChat(forSession: "s1", connection: "x") == nil)
        // The messages stay readable.
        #expect(try await store.messages(inChat: chat.id, connection: "x").map(\.text) == ["hello"])
        await #expect(throws: OfflineChatError.chatClosed) {
            try await store.append(.user, text: "late", toChat: chat.id, connection: "x", at: later(11))
        }

        let next = try await store.openChat(forSession: "s1", connection: "x", title: "Second", at: later(20))
        #expect(next.id != chat.id)
        let all = try await store.chats(connection: "x", limit: 10)
        #expect(all.map(\.title) == ["Second", "First"])
        #expect(all.map(\.resolution) == [nil, .sent])
        #expect(all.last?.updatedAt == later(10))
    }

    @Test func aClosedChatKeepsItsFirstResolution() async throws {
        let store = try HermesCache().offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "t", at: start)
        try await store.resolve(chat: chat.id, connection: "x", as: .dismissed, at: later(1))
        try await store.resolve(chat: chat.id, connection: "x", as: .sent, at: later(2))
        let stored = try await store.chats(connection: "x", limit: 10)
        #expect(stored.first?.resolution == .dismissed)
        #expect(stored.first?.updatedAt == later(1))
    }

    @Test func chatsComeBackNewestFirstAndRespectTheLimit() async throws {
        let store = try HermesCache().offlineChats
        for index in 0..<4 {
            let chat = try await store.openChat(
                forSession: "s\(index)", connection: "x", title: "chat \(index)", at: later(Double(index)))
            _ = try await store.append(
                .user, text: "m", toChat: chat.id, connection: "x", at: later(Double(index)))
        }
        #expect(
            try await store.chats(connection: "x", limit: 10).map(\.title) == ["chat 3", "chat 2", "chat 1", "chat 0"])
        #expect(try await store.chats(connection: "x", limit: 2).map(\.title) == ["chat 3", "chat 2"])
    }

    @Test func deletingAChatRemovesItsMessages() async throws {
        let store = try HermesCache().offlineChats
        let doomed = try await store.openChat(forSession: "s1", connection: "x", title: "doomed", at: start)
        let kept = try await store.openChat(forSession: "s2", connection: "x", title: "kept", at: start)
        _ = try await store.append(.user, text: "a", toChat: doomed.id, connection: "x", at: start)
        _ = try await store.append(.user, text: "b", toChat: kept.id, connection: "x", at: start)
        try await store.deleteChat(doomed.id, connection: "x")
        #expect(try await store.chats(connection: "x", limit: 10) == [kept])
        #expect(try await store.messages(inChat: doomed.id, connection: "x").isEmpty)
        #expect(try await store.messages(inChat: kept.id, connection: "x").count == 1)
    }

    // MARK: - Apart from the server's data

    @Test func offlineChatsNeverTouchTheServersRows() async throws {
        let cache = try HermesCache()
        try await cache.saveMessages([serverMessage(1, session: "s1")], connection: "x")
        let store = cache.offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "t", at: start)
        _ = try await store.append(.user, text: "offline question", toChat: chat.id, connection: "x", at: start)
        _ = try await store.append(.assistant, text: "offline answer", toChat: chat.id, connection: "x", at: start)

        // The server session still holds exactly its own message.
        let server = try await cache.messages(sessionID: "s1", connection: "x")
        #expect(server.map(\.content) == ["server message"])
        #expect(try await cache.messageCount(sessionID: "s1", connection: "x") == 1)
        #expect(try await cache.sessions(connection: "x").isEmpty)
    }

    @Test func removingAServerSessionKeepsItsOfflineChat() async throws {
        let cache = try HermesCache()
        let store = cache.offlineChats
        let chat = try await store.openChat(forSession: "s1", connection: "x", title: "t", at: start)
        _ = try await store.append(.user, text: "hi", toChat: chat.id, connection: "x", at: start)
        try await cache.removeSession("s1", connection: "x")
        #expect(try await store.currentChat(forSession: "s1", connection: "x") == chat)
        #expect(try await store.messages(inChat: chat.id, connection: "x").count == 1)
    }

    @Test func purgingAConnectionRemovesItsOfflineChatsOnly() async throws {
        let cache = try HermesCache()
        let store = cache.offlineChats
        let gone = try await store.openChat(forSession: "s1", connection: "x", title: "gone", at: start)
        let stays = try await store.openChat(forSession: "s1", connection: "y", title: "stays", at: start)
        _ = try await store.append(.user, text: "a", toChat: gone.id, connection: "x", at: start)
        _ = try await store.append(.user, text: "b", toChat: stays.id, connection: "y", at: start)
        try await cache.purge(connection: "x")
        #expect(try await store.chats(connection: "x", limit: 10).isEmpty)
        #expect(try await store.messages(inChat: gone.id, connection: "x").isEmpty)
        #expect(try await store.chats(connection: "y", limit: 10) == [stays])
        #expect(try await store.messages(inChat: stays.id, connection: "y").count == 1)
    }

    @Test func offlineChatsSurviveReopeningTheCacheFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("offline-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("cache.sqlite")
        let chatID: String
        do {
            let store = try HermesCache(url: url).offlineChats
            let chat = try await store.openChat(forSession: "s1", connection: "x", title: "Persisted", at: start)
            _ = try await store.append(.user, text: "still here?", toChat: chat.id, connection: "x", at: later(1))
            chatID = chat.id
        }
        // Opening again runs every migration again; the offline tables must come through untouched.
        let reopened = try HermesCache(url: url).offlineChats
        let chat = try await reopened.currentChat(forSession: "s1", connection: "x")
        #expect(chat?.id == chatID)
        #expect(chat?.title == "Persisted")
        #expect(try await reopened.messages(inChat: chatID, connection: "x").map(\.text) == ["still here?"])
    }
}
