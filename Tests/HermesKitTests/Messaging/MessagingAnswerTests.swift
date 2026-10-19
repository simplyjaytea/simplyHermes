import Foundation
import HermesKit
import Testing

/// Sample answers with the keys and JSON types of the recorded files named beside them (at commit e3dc403). The ids and
/// texts are samples: the testbed's values vary between runs, so no test relies on them as server facts.
enum MessagingRecorded {
    /// Shaped like Fixtures/rest/GET_api_messaging_platforms.json: two rows, the second with `whatsapp_setup`.
    static let platforms = #"""
        {
          "env_path": "/data/sample/.env",
          "gateway_start_command": "sample gateway start",
          "platforms": [
            {
              "id": "first", "name": "First platform", "description": "A sample platform.",
              "docs_url": "https://example.com/docs", "state": "disabled", "configured": false,
              "enabled": false, "gateway_running": false, "error_code": null, "error_message": null,
              "home_channel": null, "ingress_url": null, "updated_at": null,
              "env_vars": [
                {
                  "advanced": false, "description": "A secret.", "help": "", "is_list": false,
                  "is_password": true, "is_set": false, "key": "SAMPLE_TOKEN", "prompt": "Token",
                  "redacted_value": null, "required": true, "url": null, "value": null
                },
                {
                  "advanced": true, "description": "A list.", "help": "Comma separated.", "is_list": true,
                  "is_password": false, "is_set": true, "key": "SAMPLE_LIST", "prompt": "List",
                  "redacted_value": null, "required": false, "url": "https://example.com/list", "value": ""
                }
              ]
            },
            {
              "id": "second", "name": "Second platform", "description": "Another sample platform.",
              "docs_url": "https://example.com/second", "state": "disabled", "configured": true,
              "enabled": true, "gateway_running": false, "error_code": null, "error_message": null,
              "home_channel": null, "ingress_url": null, "updated_at": null,
              "whatsapp_setup": {"allowed_users_set": false, "home_channel_set": true, "mode": ""},
              "env_vars": []
            }
          ]
        }
        """#

    /// Shaped like Fixtures/rest/GET_api_pairing.json (200): both lists empty.
    static let pairing = #"{"approved": [], "pending": []}"#

    /// Shaped like Fixtures/rest/GET_api_webhooks.json (200): webhooks off, no subscriptions.
    static let webhooks = #"{"base_url": "http://localhost:8644", "enabled": false, "subscriptions": []}"#

    /// Shaped like the 400 of Fixtures/rest/POST_api_webhooks.json: the error envelope with `detail`.
    static let webhookCreateRefused = #"""
        {"detail": "Webhook platform is not enabled. Enable it from the Webhooks page first."}
        """#
}

/// Decodes the typed answers from samples shaped like the recorded ones, and checks the status rows built from them.
@Suite struct MessagingAnswerTests {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: Data(json.utf8))
    }

    @Test func platformListDecodesTheTypedFields() throws {
        let list = try decode(MessagingPlatformList.self, MessagingRecorded.platforms)
        #expect(list.envPath == "/data/sample/.env" && list.gatewayStartCommand == "sample gateway start")
        let first = try #require(list.platforms.first { $0.id == "first" })
        #expect(first.name == "First platform" && first.docsUrl == "https://example.com/docs")
        #expect(!first.configured && !first.enabled && !first.gatewayRunning && first.whatsappSetup == nil)
        let token = try #require(first.envVars.first { $0.key == "SAMPLE_TOKEN" })
        #expect(token.isPassword && token.required && !token.isSet && token.url == nil)
        let listSetting = try #require(first.envVars.first { $0.key == "SAMPLE_LIST" })
        #expect(listSetting.isList && listSetting.advanced && listSetting.help == "Comma separated.")
        #expect(listSetting.url == "https://example.com/list")
        let second = try #require(list.platforms.first { $0.id == "second" })
        #expect(second.envVars.isEmpty && second.configured && second.enabled)
        let setup = try #require(second.whatsappSetup)
        #expect(!setup.allowedUsersSet && setup.homeChannelSet && setup.mode == "")
    }

    @Test func platformStatusLinesHaveOneRowPerPlatformWithStateAndSetUp() throws {
        let list = try decode(MessagingPlatformList.self, MessagingRecorded.platforms)
        #expect(list.statusLines.count == list.platforms.count)
        let first = try #require(list.statusLines.first { $0.title == "First platform" })
        #expect(first.detail == "disabled, not set up")
        let second = try #require(list.statusLines.first { $0.title == "Second platform" })
        #expect(second.detail == "disabled, set up")
    }

    @Test func pairingListKeepsCountsAndRefusesAnAnswerWithoutItsLists() throws {
        let empty = try decode(PairingRequestList.self, MessagingRecorded.pairing)
        #expect(empty.pendingCount == 0 && empty.approvedCount == 0)
        let counted = try decode(PairingRequestList.self, #"{"approved": [{}], "pending": [{}, {}]}"#)
        #expect(counted.pendingCount == 2 && counted.approvedCount == 1)
        #expect(counted.statusLines.map(\.detail) == ["2", "1"])
        #expect(throws: DecodingError.self) {
            _ = try decode(PairingRequestList.self, #"{"approved": []}"#)
        }
    }

    @Test func webhookListKeepsItsFieldsAndCountsSubscriptions() throws {
        let list = try decode(WebhookList.self, MessagingRecorded.webhooks)
        #expect(list.baseUrl == "http://localhost:8644" && !list.enabled && list.subscriptionCount == 0)
        #expect(list.statusLines.map(\.title) == ["Webhooks", "Base URL", "Subscriptions"])
        let busy = try decode(WebhookList.self, #"{"base_url": "http://x", "enabled": true, "subscriptions": [{}]}"#)
        #expect(busy.enabled && busy.subscriptionCount == 1)
        #expect(busy.statusLines.map(\.detail) == ["On", "http://x", "1"])
    }
}
