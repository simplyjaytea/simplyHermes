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

@Suite struct ProfileSelectionTests {
    @Test func noChoiceFollowsTheServerDefault() throws {
        let selection = ProfileSelection.resolve(profiles: try profiles(), stored: nil)
        #expect(selection.chosen == nil && selection.current?.name == "default" && selection.label == "default")
        #expect(selection.rows.map(\.isCurrent) == [true, false, false])
    }

    @Test func aKnownChoiceIsKeptAndShownByDisplayName() throws {
        let selection = ProfileSelection.resolve(profiles: try profiles(), stored: "ops")
        #expect(selection.chosen == "ops" && selection.label == "Ops bot")
        #expect(selection.rows.map(\.title) == ["default", "Ops bot", "research"], "empty display names fall back")
        #expect(selection.rows.map(\.isCurrent) == [false, true, false])
    }

    @Test func aDeletedProfileFallsBackToTheDefault() throws {
        let selection = ProfileSelection.resolve(profiles: try profiles(), stored: "gone")
        #expect(selection.chosen == nil && selection.current?.name == "default")
    }

    @Test func noProfilesYetStillHasALabel() {
        #expect(ProfileSelection().label == "Default" && ProfileSelection().rows.isEmpty)
    }
}
