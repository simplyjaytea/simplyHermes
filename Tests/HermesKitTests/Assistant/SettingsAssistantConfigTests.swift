import Foundation
import HermesKit
import Testing

@Suite struct SettingsAssistantConfigTests {
    /// Synthetic on purpose: its keys have mixed case, to show that decoding keeps each key as sent. The recorded
    /// config document in Fixtures/rest/GET_api_config.json uses lowercase keys.
    private let answer =
        #"{"Some_Key":1,"camelKey":2,"OPENAI_API_KEY":"sk-x","nested_map":{"my_value":[1,{"A_B":null}]},"ratio":0.25}"#

    @Test func decodedAnswerKeepsEveryKeyExactly() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(answer.utf8))
        let config = try SettingsAssistantConfig(answer: decoded)
        #expect(Set(config.values.keys) == ["Some_Key", "camelKey", "OPENAI_API_KEY", "nested_map", "ratio"])
        #expect(config.document == decoded)
        #expect(config.value(at: ["nested_map", "my_value"]) == .array([.int(1), .object(["A_B": .null])]))
        #expect(config.value(at: ["ratio"]) == .double(0.25))
        #expect(config.value(at: ["missing", "key"]) == nil)
    }

    @Test func aNonObjectAnswerIsRefused() {
        #expect(throws: SettingsAssistantConfigError.notAnObject(path: [])) {
            try SettingsAssistantConfig(answer: .array([]))
        }
    }

    @Test func setCreatesMissingObjectsAndReplacesNull() throws {
        // Keys are recorded in GET_api_config.json: voice, terminal and curator. Values are canned.
        var config = SettingsAssistantConfig(values: [
            "terminal": .null,
            "voice": .object(["beep_volume": .double(0.3)]),
        ])
        try config.set(.string("."), at: ["terminal", "cwd"])
        try config.set(.bool(true), at: ["voice", "barge_in"])
        try config.set(.int(24), at: ["curator", "interval_hours"])
        #expect(config.value(at: ["terminal", "cwd"]) == .string("."))
        #expect(config.value(at: ["voice"]) == .object(["beep_volume": .double(0.3), "barge_in": .bool(true)]))
        #expect(config.value(at: ["curator", "interval_hours"]) == .int(24))
        #expect(config.values.count == 3)
    }

    @Test func setRefusesToReplaceAScalarOnThePath() {
        var config = SettingsAssistantConfig(values: ["voice": .string("on")])
        #expect(throws: SettingsAssistantConfigError.notAnObject(path: ["voice"])) {
            try config.set(.bool(true), at: ["voice", "barge_in"])
        }
        #expect(config.value(at: ["voice"]) == .string("on"))
    }

    @Test func setNeedsAPath() {
        var config = SettingsAssistantConfig()
        #expect(throws: SettingsAssistantConfigError.emptyPath) {
            try config.set(.null, at: [])
        }
    }
}
