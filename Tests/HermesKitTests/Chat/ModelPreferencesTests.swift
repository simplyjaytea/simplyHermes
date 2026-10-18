import Foundation
import Testing

@testable import HermesKit

@Suite struct ModelPreferencesTests {
    private let small = ModelChoice(provider: "openrouter", model: "small")
    private let large = ModelChoice(provider: "anthropic", model: "large")

    private func info(_ json: String) throws -> SessionInfo {
        try JSONDecoder().decode(SessionInfo.self, from: Data(json.utf8))
    }

    @Test func starringTogglesAndKeepsOrder() {
        var preferences = ModelPreferences()
        preferences.toggleFavorite(small)
        preferences.toggleFavorite(large)
        #expect(preferences.favorites == [small, large])
        #expect(preferences.isFavorite(small))
        preferences.toggleFavorite(small)
        #expect(preferences.favorites == [large])
        #expect(!preferences.isFavorite(small))
    }

    @Test func choiceNamesTheProviderOnlyWhenItChanges() {
        #expect(large.configValue(currentProvider: "anthropic") == "large")
        #expect(large.configValue(currentProvider: "openrouter") == "anthropic:large")
        #expect(large.configValue(currentProvider: nil) == "anthropic:large")
    }

    @Test func restoreSendsNothingWhenTheChatMatches() throws {
        var preferences = ModelPreferences()
        preferences.sticky = small
        preferences.stickyEffort = "high"
        let current = try info(#"{"model":"small","provider":"openrouter","reasoning_effort":"high"}"#)
        #expect(preferences.restoreParams(for: current, sessionID: "s1").isEmpty)
    }

    @Test func restoreSwitchesModelAndEffortWhenTheChatDiffers() throws {
        var preferences = ModelPreferences()
        preferences.sticky = large
        preferences.stickyEffort = "high"
        let current = try info(#"{"model":"small","provider":"openrouter","reasoning_effort":"low"}"#)
        let params = preferences.restoreParams(for: current, sessionID: "s1")
        #expect(params.map(\.key) == ["model", "reasoning"])
        #expect(params[0].value == "anthropic:large")
        #expect(params[1].value == "high")
        #expect(params[1].scope == "session")
        #expect(params.allSatisfy { $0.sessionID == "s1" })
    }

    @Test func restoreLeavesTheEffortAloneWhenTheModelReportsNone() throws {
        var preferences = ModelPreferences()
        preferences.stickyEffort = "high"
        let current = try info(#"{"model":"small","provider":"openrouter","reasoning_effort":""}"#)
        #expect(preferences.restoreParams(for: current, sessionID: "s1").isEmpty)
    }

    @Test func savedPreferencesComeBackFromDefaults() throws {
        let suite = "ModelPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ModelPreferencesStore.load(from: defaults) == ModelPreferences())

        var preferences = ModelPreferences()
        preferences.toggleFavorite(large)
        preferences.sticky = small
        preferences.stickyEffort = "high"
        ModelPreferencesStore.save(preferences, to: defaults)
        #expect(ModelPreferencesStore.load(from: defaults) == preferences)
    }
}
