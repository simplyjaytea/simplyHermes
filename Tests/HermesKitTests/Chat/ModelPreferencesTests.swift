import Foundation
import Testing

@testable import HermesKit

@Suite struct ModelPreferencesTests {
    private let small = ModelChoice(provider: "openrouter", model: "small")
    private let large = ModelChoice(provider: "anthropic", model: "large")
    private let fake = ModelChoice(provider: "custom", model: "fake-model")

    /// A `model.options` answer. openrouter lists "small" (reasons, can run with reasoning off) and "plain" (does not
    /// reason). anthropic lists "large" (reasons, cannot run with reasoning off).
    private let serverJSON = """
        {"model":"small","provider":"openrouter","providers":[
        {"slug":"openrouter","name":"OpenRouter","models":["small","plain"],"capabilities":{
        "small":{"fast":false,"reasoning":true,"can_disable_reasoning":true},
        "plain":{"fast":false,"reasoning":false}}},
        {"slug":"anthropic","name":"Anthropic","models":["large"],"capabilities":{
        "large":{"fast":false,"reasoning":true}}}]}
        """

    private func info(_ json: String) throws -> SessionInfo {
        try JSONDecoder().decode(SessionInfo.self, from: Data(json.utf8))
    }

    private func options(_ json: String) throws -> ModelOptionsResult {
        try JSONDecoder().decode(ModelOptionsResult.self, from: Data(json.utf8))
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
        let server = try options(serverJSON)
        #expect(preferences.restoreParams(for: current, sessionID: "s1", options: server).isEmpty)
    }

    @Test func restoreSwitchesModelAndEffortWhenTheChatDiffers() throws {
        var preferences = ModelPreferences()
        preferences.sticky = large
        preferences.stickyEffort = "high"
        let current = try info(#"{"model":"small","provider":"openrouter","reasoning_effort":"low"}"#)
        let server = try options(serverJSON)
        let params = preferences.restoreParams(for: current, sessionID: "s1", options: server)
        #expect(params.map(\.key) == ["model", "reasoning"])
        #expect(params[0].value == "anthropic:large")
        #expect(params[1].value == "high")
        #expect(params[1].scope == "session")
        #expect(params.allSatisfy { $0.sessionID == "s1" })
    }

    @Test func restoreLeavesTheEffortAloneWhenTheModelDoesNotReason() throws {
        var preferences = ModelPreferences()
        preferences.stickyEffort = "high"
        let current = try info(#"{"model":"plain","provider":"openrouter","reasoning_effort":""}"#)
        let server = try options(serverJSON)
        #expect(preferences.restoreParams(for: current, sessionID: "s1", options: server).isEmpty)
    }

    @Test func restoreNeverSendsAModelTheServerDoesNotList() throws {
        // The recorded testbed answer lists only custom / fake-model.
        let recorded = try options(restFixture("model_options"))
        let current = try info(#"{"model":"fake-model","provider":"custom","reasoning_effort":"high"}"#)
        var preferences = ModelPreferences()
        preferences.stickyEffort = "high"
        // A pick made on another server that also calls its provider "custom".
        preferences.sticky = ModelChoice(provider: "custom", model: "other-server-model")
        #expect(preferences.restoreParams(for: current, sessionID: "s1", options: recorded).isEmpty)
        // The right name under another provider slug is not the same model.
        preferences.sticky = ModelChoice(provider: "openrouter", model: "fake-model")
        #expect(preferences.restoreParams(for: current, sessionID: "s1", options: recorded).isEmpty)
    }

    @Test func restoreSetsTheEffortOnADefaultConfigWhereSessionInfoReportsNone() throws {
        // The recorded answers: session.info has an empty reasoning_effort and model.options says the model reasons.
        let recorded = try options(restFixture("model_options"))
        let current = try info(#"{"model":"fake-model","provider":"custom","reasoning_effort":""}"#)
        var preferences = ModelPreferences()
        preferences.stickyEffort = "high"
        let params = preferences.restoreParams(for: current, sessionID: "s1", options: recorded)
        #expect(params.map(\.key) == ["reasoning"])
        #expect(params.first?.value == "high")
        #expect(params.first?.scope == "session")
    }

    @Test func restoreSendsNoneOnlyForAModelThatCanRunWithoutReasoning() throws {
        var preferences = ModelPreferences()
        preferences.stickyEffort = "none"
        let onSmall = try info(#"{"model":"small","provider":"openrouter","reasoning_effort":"low"}"#)
        let onLarge = try info(#"{"model":"large","provider":"anthropic","reasoning_effort":"low"}"#)
        let server = try options(serverJSON)
        #expect(preferences.restoreParams(for: onSmall, sessionID: "s1", options: server).map(\.value) == ["none"])
        #expect(preferences.restoreParams(for: onLarge, sessionID: "s1", options: server).isEmpty)
    }

    @Test func favoritesShowOnlyWhatTheServerLists() throws {
        var preferences = ModelPreferences()
        preferences.toggleFavorite(small)
        preferences.toggleFavorite(fake)
        preferences.toggleFavorite(large)
        let server = try options(serverJSON)
        let recorded = try options(restFixture("model_options"))
        #expect(preferences.listedFavorites(in: server) == [small, large])
        #expect(preferences.listedFavorites(in: recorded) == [fake])
        // The star stays for the server that has the model.
        #expect(preferences.favorites == [small, fake, large])
    }

    @Test func optionsReportWhichModelsReasonAndWhetherReasoningCanBeOff() throws {
        let server = try options(serverJSON)
        #expect(server.currentChoice == small)
        let all = ["none", "minimal", "low", "medium", "high", "xhigh"]
        #expect(server.reasoningLevels(for: small) == all)
        #expect(server.reasoningLevels(for: large) == Array(all.dropFirst()))
        #expect(server.reasoningLevels(for: ModelChoice(provider: "openrouter", model: "plain")).isEmpty)
        #expect(server.reasoningLevels(for: ModelChoice(provider: "openrouter", model: "unlisted")).isEmpty)
        #expect(server.reasoningLevels(for: ModelChoice(provider: "unknown", model: "small")).isEmpty)
        #expect(!server.lists(ModelChoice(provider: "anthropic", model: "small")))
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
