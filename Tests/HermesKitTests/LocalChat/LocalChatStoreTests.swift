import Foundation
import GRDB
import Testing

@testable import HermesKit

struct LocalChatStoreTests {
    @Test func messagesAndTheModelThatWroteEachReplySurviveAReopen() async throws {
        let url = try temporaryDatabaseURL()
        let id = UUID()
        let gemma = ModelIdentity.downloaded(id: "gemma-3-1b-4bit", displayName: "Gemma 3 1B")
        do {
            let store = try HermesCache(url: url).localChats
            _ = try await store.createChat(id: id, title: "Trip", at: localChatStart)
            _ = try await store.appendUserMessage("Hello", toChat: id, at: localChatStart)
            _ = try await store.appendReply(
                LocalReply(text: "Hi from Apple", answeredBy: .apple), toChat: id, at: localChatStart)
            _ = try await store.appendReply(
                LocalReply(text: "Hi from Gemma", answeredBy: gemma), toChat: id, at: localChatStart)
        }

        // A new database queue on the same file, as after a relaunch.
        let reopened = GRDBLocalChatStore(database: try DatabaseQueue(path: url.path))
        let messages = try await reopened.messages(inChat: id)
        #expect(messages.map(\.text) == ["Hello", "Hi from Apple", "Hi from Gemma"])
        #expect(messages.map(\.id) == [1, 2, 3])
        #expect(messages[0].author == .user)
        #expect(messages[1].author == .assistant(answeredBy: .apple))
        #expect(messages[2].author == .assistant(answeredBy: gemma))
        #expect(try await reopened.chat(id)?.title == "Trip")
    }

    @Test func aMessageCannotJoinAChatThatDoesNotExist() async throws {
        let store = try HermesCache().localChats
        await #expect(throws: LocalChatError.chatNotFound) {
            _ = try await store.appendUserMessage("orphan", toChat: UUID(), at: localChatStart)
        }
        await #expect(throws: LocalChatError.chatNotFound) {
            _ = try await store.appendReply(
                LocalReply(text: "orphan", answeredBy: .apple), toChat: UUID(), at: localChatStart)
        }
    }

    @Test func chatsListNewestFirstAndDeletingRemovesItsMessages() async throws {
        let store = try HermesCache().localChats
        let older = UUID()
        let newer = UUID()
        _ = try await store.createChat(id: older, title: "Older", at: localChatStart)
        _ = try await store.createChat(id: newer, title: "Newer", at: localChatStart.addingTimeInterval(60))
        _ = try await store.appendUserMessage("bump", toChat: older, at: localChatStart.addingTimeInterval(120))

        #expect(try await store.chats(limit: 10).map(\.id) == [older, newer])

        try await store.deleteChat(older)
        #expect(try await store.chat(older) == nil)
        #expect(try await store.messages(inChat: older).isEmpty)
        #expect(try await store.chats(limit: 10).map(\.id) == [newer])
    }

    @Test func aPurgeOfAServerConnectionKeepsLocalChats() async throws {
        let cache = try HermesCache()
        let id = UUID()
        _ = try await cache.localChats.createChat(id: id, title: "Stays", at: localChatStart)
        try await cache.purge(connection: "any")
        #expect(try await cache.localChats.chat(id)?.title == "Stays")
    }
}

struct LocalChatMigrationTests {
    @Test func offlineChatsFromTheCurrentSchemaBecomeStandaloneLocalChats() async throws {
        let url = try temporaryDatabaseURL()
        let open = UUID()
        let resolved = UUID()
        do {
            // The schema the app shipped before WP-7: the offline chat tables exist, keyed to a server session.
            let older = try DatabaseQueue(path: url.path)
            try HermesCache.migrator.migrate(older, upTo: "outbox-v1")
            try await older.write { handle in
                for (chat, title, resolution) in [(open, "Open offline", nil as String?), (resolved, "Sent", "sent")] {
                    try handle.execute(
                        sql: """
                            INSERT INTO offline_chat (connection, chat_id, session_id, title, created_at, updated_at, resolution)
                            VALUES ('conn-1', ?, 'server-session', ?, ?, ?, ?)
                            """,
                        arguments: [
                            chat.uuidString, title, localChatStart.timeIntervalSince1970,
                            localChatStart.addingTimeInterval(5).timeIntervalSince1970, resolution,
                        ])
                }
                for (message, role, text) in [(1, "user", "question"), (2, "assistant", "answer")] {
                    try handle.execute(
                        sql: """
                            INSERT INTO offline_message (connection, chat_id, message_id, role, text, created_at)
                            VALUES ('conn-1', ?, ?, ?, ?, ?)
                            """,
                        arguments: [open.uuidString, message, role, text, localChatStart.timeIntervalSince1970])
                }
            }
        }

        let upgraded = try HermesCache(url: url)
        let chats = try await upgraded.localChats.chats(limit: 10)
        #expect(Set(chats.map(\.id)) == [open, resolved])
        #expect(chats.first { $0.id == open }?.title == "Open offline")

        let messages = try await upgraded.localChats.messages(inChat: open)
        #expect(messages.map(\.text) == ["question", "answer"])
        #expect(messages[0].author == .user)
        // The offline chat never recorded which model answered, so the reply keeps no model rather than a guess.
        #expect(messages[1].author == .assistant(answeredBy: nil))

        let tables = try tableNames(at: url)
        #expect(!tables.contains("offline_chat"))
        #expect(!tables.contains("offline_message"))
    }
}
