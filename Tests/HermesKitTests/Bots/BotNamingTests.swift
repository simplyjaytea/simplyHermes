import Testing

@testable import HermesKit

@Suite struct BotNamingTests {
    @Test func slugFoldsAccentsAndDropsPunctuation() {
        #expect(BotNaming.slug("My Bot!") == "my-bot")
        #expect(BotNaming.slug("  Ops_Team  ") == "ops_team")
        #expect(BotNaming.slug("Café") == "cafe")
    }

    @Test func slugKeepsLettersWithoutAsciiFormAsCodePoints() {
        #expect(BotNaming.slug("東京") == "u6771-u4eac")
    }

    @Test func profileNameRules() {
        #expect(BotNaming.isValidProfileName("ops"))
        #expect(BotNaming.isValidProfileName("a"))
        #expect(BotNaming.isValidProfileName("ops-2_b"))
        #expect(BotNaming.isValidProfileName(String(repeating: "a", count: 64)))
        #expect(!BotNaming.isValidProfileName(String(repeating: "a", count: 65)))
        #expect(!BotNaming.isValidProfileName(""))
        #expect(!BotNaming.isValidProfileName("-ops"))
        #expect(!BotNaming.isValidProfileName("_ops"))
        #expect(!BotNaming.isValidProfileName("Ops"))
        #expect(!BotNaming.isValidProfileName("a b"))
        #expect(!BotNaming.isValidProfileName("hermes"))
    }

    @Test func labelSlugForClashingHandles() {
        #expect(BotNaming.labelSlug("My Phone (2)") == "my-phone-2")
        #expect(BotNaming.labelSlug("   ") == "connection")
    }

    @Test func displayNamePrefersTitleThenDisplayNameThenProfile() {
        #expect(BotNaming.displayName(profile: "ops", title: "Ops Bot", displayName: "Other") == "Ops Bot")
        #expect(BotNaming.displayName(profile: "ops", title: "  ", displayName: "Other") == "Other")
        #expect(BotNaming.displayName(profile: "default", title: nil, displayName: nil) == "Hermes")
        #expect(BotNaming.displayName(profile: "research-bot_v2", title: nil, displayName: nil) == "Research Bot V2")
    }

    @Test func defaultIsMentionedAsHermes() {
        #expect(BotNaming.mentionHandle("default") == "@hermes")
        #expect(BotNaming.mentionHandle("ops") == "@ops")
    }
}
