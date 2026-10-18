import Foundation
import HermesKit
import Testing

/// Synthetic answers: these check the row renderer, not a server shape. The recorded case is
/// `recordedSecretFieldIsMarked`.
@Suite struct SettingsAssistantRowsTests {
    @Test func rowsFollowSortedKeysAndArrayOrder() {
        let answer: JSONValue = ["zeta": 1, "alpha": ["beta": [true, nil]], "empty": [:], "list": []]
        let rows = SettingsAssistantRows.rows(for: answer)
        #expect(rows.map(\.label) == ["alpha.beta.0", "alpha.beta.1", "empty", "list", "zeta"])
        #expect(rows.map(\.value) == ["true", "null", "{}", "[]", "1"])
        #expect(rows.allSatisfy { !$0.isSecret })
    }

    @Test func scalarsKeepTheirTextForm() {
        let rows = SettingsAssistantRows.rows(for: ["ratio": 1.5, "count": 3, "flag": false, "name": "Ops"])
        #expect(rows.map(\.label) == ["count", "flag", "name", "ratio"])
        #expect(rows.map(\.value) == ["3", "false", "Ops", "1.5"])
    }

    @Test func aBareValueHasAnEmptyLabel() {
        let rows = SettingsAssistantRows.rows(for: .string("ready"))
        #expect(rows == [SettingsAssistantRow(path: [], value: "ready", isSecret: false)])
        #expect(rows.first?.label == "")
    }

    @Test func secretKeysAndTheirValuesAreMarked() {
        let answer: JSONValue = [
            "api_key": "placeholder",
            "providers": [["name": "honcho", "token": "placeholder"]],
            "keys": ["primary": "placeholder"],
            "voice": ["enabled": true],
        ]
        let rows = SettingsAssistantRows.rows(for: answer)
        let secrets = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0.isSecret) })
        #expect(
            secrets == [
                "api_key": true, "providers.0.name": false, "providers.0.token": true, "keys.primary": true,
                "voice.enabled": false,
            ])
    }

    @Test func recordedSecretFieldIsMarked() {
        // Keys from auxiliary.curator in GET_api_config.json. Values are canned.
        let answer: JSONValue = ["auxiliary": ["curator": ["api_key": "", "model": "", "timeout": 600]]]
        let rows = SettingsAssistantRows.rows(for: answer)
        #expect(
            rows.map(\.label) == ["auxiliary.curator.api_key", "auxiliary.curator.model", "auxiliary.curator.timeout"])
        #expect(rows.map(\.isSecret) == [true, false, false])
    }

    @Test func secretKeyNamesMatchWithoutRegardToCase() {
        #expect(SettingsAssistantRows.isSecretKey("API_KEY"))
        #expect(SettingsAssistantRows.isSecretKey("Password"))
        #expect(SettingsAssistantRows.isSecretKey("oauth_token"))
        #expect(!SettingsAssistantRows.isSecretKey("voice"))
        #expect(!SettingsAssistantRows.isSecretKey("enabled"))
    }
}

@Suite struct SettingsAssistantErrorTextTests {
    @Test func errorTextPassesServerMessages() {
        #expect(
            SettingsAssistantErrorText.message(for: RESTError.http(status: 400, detail: "identifier is required"))
                == "identifier is required")
        #expect(
            SettingsAssistantErrorText.message(for: RESTError.http(status: 500, detail: nil))
                == "The server answered with status 500.")
        #expect(
            SettingsAssistantErrorText.message(
                for: RESTError.http(status: 404, detail: "byterover does not support OAuth connect"))
                == "This server doesn't have this setting yet.")
        #expect(
            SettingsAssistantErrorText.message(for: SettingsAssistantFailure.noServer) == "Choose a server first.")
        #expect(SettingsAssistantErrorText.message(for: RESTError.transport("refused")) == "Couldn't reach the server.")
        #expect(
            SettingsAssistantErrorText.message(for: ConnectionUnavailable(phase: .idle))
                == "Connect to the server first.")
    }
}
