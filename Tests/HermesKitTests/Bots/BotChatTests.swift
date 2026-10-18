import Foundation
import Testing

@testable import HermesKit

@Suite struct BotChatTests {
    @Test func resetCommandsBecomeCompactOnlyInBotChat() {
        #expect(BotChat.rewrite("/new", inBotChat: true) == "/compact")
        #expect(BotChat.rewrite("  /reset \n", inBotChat: true) == "/compact")
        #expect(BotChat.rewrite("/new please", inBotChat: true) == "/new please")
        #expect(BotChat.rewrite("/new", inBotChat: false) == "/new")
    }

    @Test func lineageRootDecidesWhetherARowIsTheBotChat() throws {
        let lineage = try JSONDecoder().decode(
            BotChatRow.self,
            from: Data(
                #"{"id": "s1", "resolved_id": "s2", "root_title": "Bot Chat", "title": "Bot Chat (2)", "live_message_count": 3}"#
                    .utf8))
        #expect(lineage.isBotChat)
        #expect(lineage.openID == "s2")
        #expect(lineage.liveMessageCount == 3)

        let otherRoot = BotChatRow(id: "s3", rootTitle: "Sessions", title: "Bot Chat")
        #expect(!otherRoot.isBotChat)

        let untitledRoot = BotChatRow(id: "s4", title: "Bot Chat")
        #expect(untitledRoot.isBotChat)
        #expect(untitledRoot.openID == "s4")
    }

    @Test func lookupFindsTheChatAndFailsClosed() {
        let chat = BotChatRow(id: "s1", resolvedID: "s9", rootTitle: "Bot Chat")
        #expect(BotChatLookup.resolve([chat], rosterKnowsChat: true) == .found(openID: "s9", registryID: "s1"))
        #expect(BotChatLookup.resolve([], rosterKnowsChat: false) == .none)
        #expect(BotChatLookup.resolve([], rosterKnowsChat: true) == .inconsistent)
        #expect(BotChatLookup.resolve([BotChatRow(id: "s2", title: "Plans")], rosterKnowsChat: false) == .none)
    }
}
