import Foundation
import HermesKit
import Testing

private func profiles() throws -> [HermesProfile] {
    let json = """
        [{"name":"default","is_default":true},
         {"name":"ops","display_name":"Ops bot"},
         {"name":"research","display_name":""}]
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([HermesProfile].self, from: Data(json.utf8))
}

@Suite struct AppliesToTests {
    @Test func followingTheActiveProfileIsTheDefault() throws {
        let list = try profiles()
        #expect(AppliesTo.activeProfile.target(in: list, active: "default") == "default")
        #expect(AppliesTo.activeProfile.chipTitle(in: list, active: "default") == "Active profile")
    }

    @Test func pickingAnotherProfileEditsThatOneWhileTheActiveOneStaysPut() throws {
        let list = try profiles()
        let choice = AppliesTo.picking("ops", active: "default")
        #expect(choice == .profile("ops"))
        #expect(choice.target(in: list, active: "default") == "ops")
        #expect(choice.chipTitle(in: list, active: "default") == "Ops bot", "the chip shows the display name")
        // The active profile is a separate input: picking changes what the page edits, not who is active.
        #expect(AppliesTo.activeProfile.target(in: list, active: "default") == "default")
    }

    @Test func pickingTheActiveProfileMeansFollowingIt() throws {
        #expect(AppliesTo.picking("default", active: "default") == .activeProfile)
        #expect(AppliesTo.picking("research", active: "default") == .profile("research"))
        #expect(AppliesTo.picking("ops", active: nil) == .profile("ops"))
    }

    @Test func aStaleNameFallsBackToTheActiveProfile() throws {
        let list = try profiles()
        let stale = AppliesTo.profile("deleted-bot")
        #expect(stale.target(in: list, active: "default") == "default")
        #expect(stale.normalized(in: list, active: "default") == .activeProfile)
        #expect(stale.chipTitle(in: list, active: "default") == "Active profile")
    }

    @Test func aChoiceOfTheActiveProfileNormalizesToFollowing() throws {
        let list = try profiles()
        #expect(AppliesTo.profile("default").normalized(in: list, active: "default") == .activeProfile)
        #expect(AppliesTo.profile("ops").normalized(in: list, active: "default") == .profile("ops"))
    }

    @Test func noActiveProfileHasNoTarget() throws {
        #expect(AppliesTo.activeProfile.target(in: try profiles(), active: nil) == nil)
        #expect(AppliesTo.profile("ops").target(in: [], active: nil) == nil)
    }

    @Test func theSelectorIsShownOnlyWithTwoOrMoreProfiles() throws {
        let list = try profiles()
        #expect(!AppliesTo.isShown(for: []))
        #expect(!AppliesTo.isShown(for: Array(list.prefix(1))))
        #expect(AppliesTo.isShown(for: Array(list.prefix(2))))
        #expect(AppliesTo.isShown(for: list))
    }

    @Test func aChangeOfActiveProfileResetsTheChoice() throws {
        #expect(AppliesTo.profile("ops").afterActiveChange(from: "default", to: "research") == .activeProfile)
        #expect(AppliesTo.profile("ops").afterActiveChange(from: "default", to: nil) == .activeProfile)
        #expect(AppliesTo.profile("ops").afterActiveChange(from: "default", to: "default") == .profile("ops"))
        #expect(AppliesTo.activeProfile.afterActiveChange(from: "default", to: "ops") == .activeProfile)
    }

    @Test func aChangeOfServerResetsTheChoiceEvenWithTheSameProfileName() throws {
        let choice = AppliesTo.profile("ops")
        #expect(choice.afterActiveChange(from: "server-a/default", to: "server-b/default") == .activeProfile)
        #expect(choice.afterActiveChange(from: "server-a/default", to: "server-a/default") == choice)
    }

    @Test func menuRowsFollowFirstThenTheOtherProfilesInServerOrder() throws {
        let rows = AppliesTo.profile("ops").options(in: try profiles(), active: "default")
        #expect(rows.map(\.title) == ["Follows the active profile", "Ops bot", "research"])
        #expect(rows[0].detail == "default", "the first row names the active profile")
        #expect(rows.map(\.isSelected) == [false, true, false])
        #expect(Set(rows.map(\.id)).count == rows.count, "ids are unique")
    }

    @Test func aStaleChoiceShowsFollowingAsSelected() throws {
        let rows = AppliesTo.profile("deleted-bot").options(in: try profiles(), active: "default")
        #expect(rows.map(\.isSelected) == [true, false, false])
    }

    @Test func followingIsTheOnlyRowWhenThereIsNoOtherProfile() throws {
        let only = Array(try profiles().prefix(1))
        let rows = AppliesTo.activeProfile.options(in: only, active: "default")
        #expect(rows.count == 1 && rows[0].isSelected && rows[0].choice == .activeProfile)
    }
}
