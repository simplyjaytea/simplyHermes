import Foundation
import HermesKit
import Testing

@Suite struct SettingsAssistantConfigTests {
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
        var config = SettingsAssistantConfig(values: [
            "terminal": .null,
            "voice": .object(["speed": .double(1.5)]),
        ])
        try config.set(.string("bash"), at: ["terminal", "shell"])
        try config.set(.bool(true), at: ["voice", "enabled"])
        try config.set(.int(3), at: ["agent", "max_turns"])
        #expect(config.value(at: ["terminal", "shell"]) == .string("bash"))
        #expect(config.value(at: ["voice"]) == .object(["speed": .double(1.5), "enabled": .bool(true)]))
        #expect(config.value(at: ["agent", "max_turns"]) == .int(3))
        #expect(config.values.count == 3)
    }

    @Test func setRefusesToReplaceAScalarOnThePath() {
        var config = SettingsAssistantConfig(values: ["voice": .string("on")])
        #expect(throws: SettingsAssistantConfigError.notAnObject(path: ["voice"])) {
            try config.set(.bool(true), at: ["voice", "enabled"])
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
