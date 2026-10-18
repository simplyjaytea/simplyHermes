import Foundation
import HermesKit
import Testing

/// A `profiles.list` answer shaped like the contract's ProfilesListResult, with a row each for the three cases that
/// matter: a bot with a session and a display name, a bot with empty text and a preview-only session, and no session.
private let roster = """
    {"profiles":[
      {"name":"default","path":"/data/hermes","is_default":true,"model":"fake-model","provider":"custom",
       "description":"","display_name":"","skill_count":3,"previous_names":[],"last_session":null,
       "ui_meta_revisions":{},"has_avatar":false},
      {"name":"ops","path":"/data/hermes/profiles/ops","is_default":false,"model":"gpt-x","provider":"openai",
       "description":"Ops bot","display_name":"Ops bot","skill_count":7,"previous_names":[],
       "last_session":{"id":"s9","title":"Deploy plan","preview":"ship it","started_at":1699999000,
         "last_active":1700000000,"message_count":4},
       "ui_meta_revisions":{},"has_avatar":true},
      {"name":"research","path":"/data/hermes/profiles/research","is_default":false,"model":"","provider":null,
       "description":"","display_name":"","skill_count":0,"previous_names":[],
       "last_session":{"id":"s2","title":"","preview":"  what is a cron job  ","started_at":0,"last_active":0,
         "message_count":0},
       "ui_meta_revisions":{}}
    ],"bot_mode_protocol":true,"install_id":"install-1"}
    """

@Suite struct BotFactsTests {
    private func facts() throws -> [BotFacts] {
        let result = try JSONDecoder().decode(ProfilesListResult.self, from: Data(roster.utf8))
        return result.profiles.map(BotFacts.init(row:))
    }

    @Test func aRowBecomesTheFactsBotSettingsShows() throws {
        let ops = try #require(try facts().first { $0.name == "ops" })
        #expect(ops.title == "Ops bot" && ops.model == "gpt-x" && ops.provider == "openai" && ops.skillCount == 7)
        #expect(
            ops.lastSession
                == BotFacts.LastSession(
                    title: "Deploy plan", lastActive: Date(timeIntervalSince1970: 1_700_000_000), messageCount: 4))
    }

    @Test func emptyTextIsMissingAndASessionWithoutATitleShowsItsPreview() throws {
        let list = try facts()
        let research = try #require(list.first { $0.name == "research" })
        #expect(research.title == "research" && research.model == nil && research.provider == nil)
        #expect(
            research.lastSession
                == BotFacts.LastSession(title: "what is a cron job", lastActive: nil, messageCount: 0),
            "a zero last_active is no time, and the preview is trimmed")
    }

    @Test func aBotWithoutASessionHasNoLastSession() throws {
        let defaultBot = try #require(try facts().first { $0.name == "default" })
        #expect(defaultBot.lastSession == nil && defaultBot.skillCount == 3 && defaultBot.id == "default")
    }
}
