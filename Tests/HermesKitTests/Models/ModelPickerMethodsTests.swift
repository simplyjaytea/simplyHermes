import Foundation
import Testing

@testable import HermesKit

@Suite struct ModelPickerMethodsTests {
    @Test func configSetParamsUseTheWireKeys() throws {
        let params = ConfigSetParams(key: "reasoning", value: "high", sessionID: "s1", scope: "session")
        let data = try JSONEncoder().encode(params)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""key":"reasoning""#))
        #expect(json.contains(#""value":"high""#))
        #expect(json.contains(#""session_id":"s1""#))
        #expect(json.contains(#""scope":"session""#))
        #expect(json.contains(#""confirm_expensive_model":false"#))
    }

    @Test func expensiveModelWaitsForConfirmation() throws {
        let json =
            #"{"key":"model","value":"large","confirm_required":true,"#
            + #""confirm_message":"Costs more per turn."}"#
        let result = try JSONDecoder().decode(ConfigSetResult.self, from: Data(json.utf8))
        #expect(result.outcome == .needsConfirmation(message: "Costs more per turn."))
    }

    @Test func appliedSwitchKeepsItsWarning() throws {
        let json = #"{"key":"model","value":"small","warning":"This model has no tool calls."}"#
        let result = try JSONDecoder().decode(ConfigSetResult.self, from: Data(json.utf8))
        #expect(result.outcome == .applied(warning: "This model has no tool calls."))
    }

    @Test func plainResultIsApplied() throws {
        let json = #"{"key":"reasoning","value":"high","scope":"session"}"#
        let result = try JSONDecoder().decode(ConfigSetResult.self, from: Data(json.utf8))
        #expect(result.outcome == .applied(warning: nil))
    }
}
