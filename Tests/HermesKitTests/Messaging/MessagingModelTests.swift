import Foundation
import HermesKit
import Testing

/// Request models decode from the schema's snake_case keys, leave unset fields out and ignore unknown keys.
@Suite struct MessagingModelTests {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Value.self, from: Data(json.utf8))
    }

    private func encodedKeys(_ value: some Encodable) throws -> Set<String> {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value))
        return Set((object as? [String: Any] ?? [:]).keys)
    }

    @Test func platformUpdateDecodesAndKeepsEnvKeysExact() throws {
        let update = try decode(
            MessagingPlatformUpdate.self,
            #"{"enabled":false,"env":{"TELEGRAM_BOT_TOKEN":"123:abc"},"clear_env":["OLD_KEY"],"extra":1}"#)
        #expect(
            update
                == MessagingPlatformUpdate(
                    enabled: false, env: ["TELEGRAM_BOT_TOKEN": "123:abc"], clearEnv: ["OLD_KEY"]))
        #expect(try encodedKeys(update) == ["enabled", "env", "clear_env"])
    }

    @Test func telegramStartAndApplyDecode() throws {
        #expect(try decode(MessagingTelegramStart.self, "{}") == MessagingTelegramStart())
        #expect(try decode(MessagingTelegramStart.self, #"{"bot_name":"simply bot"}"#).botName == "simply bot")
        let apply = try decode(MessagingTelegramApply.self, #"{"allowed_user_ids":["11"],"profile":"ops"}"#)
        #expect(apply == MessagingTelegramApply(allowedUserIds: ["11"], profile: "ops"))
        #expect(try encodedKeys(apply) == ["allowed_user_ids", "profile"])
    }

    @Test func whatsAppStartAndApplyDecode() throws {
        let start = try decode(MessagingWhatsAppStart.self, #"{"mode":"bot","allowed_users":""}"#)
        #expect(start == MessagingWhatsAppStart(mode: "bot", allowedUsers: ""))
        #expect(try encodedKeys(MessagingWhatsAppStart()).isEmpty)
        let apply = try decode(MessagingWhatsAppApply.self, #"{"mode":"bot"}"#)
        #expect(apply == MessagingWhatsAppApply(mode: "bot") && apply.allowedUsers == nil)
    }

    @Test func pairingApproveAndRevokeDecode() throws {
        let approve = try decode(PairingApprove.self, #"{"platform":"telegram","code":"ABC123","request_id":""}"#)
        #expect(approve == PairingApprove(platform: "telegram", code: "ABC123", requestId: ""))
        #expect(try encodedKeys(approve) == ["platform", "code", "request_id"])
        let revoke = try decode(PairingRevoke.self, #"{"platform":"telegram","user_id":"7"}"#)
        #expect(revoke == PairingRevoke(platform: "telegram", userId: "7"))
        #expect(try encodedKeys(revoke) == ["platform", "user_id"])
    }

    @Test func webhookCreateDecodesWithServerDefaults() throws {
        let create = try decode(
            WebhookCreate.self,
            #"{"name":"deploy","events":["push"],"skills":[],"deliver":"log","deliver_only":true,"deliver_chat_id":"42","secret":"s"}"#
        )
        #expect(
            create
                == WebhookCreate(
                    name: "deploy", events: ["push"], deliver: "log", deliverOnly: true, deliverChatId: "42",
                    secret: "s"))
        let minimal = WebhookCreate(name: "only")
        #expect(try encodedKeys(minimal) == ["name", "events", "skills", "deliver", "deliver_only"])
    }

    @Test func webhookEnabledToggleDecodesAndEncodes() throws {
        let toggle = try decode(WebhookEnabledToggle.self, #"{"enabled":true}"#)
        #expect(toggle == WebhookEnabledToggle(enabled: true))
        #expect(try encodedKeys(toggle) == ["enabled"])
    }

    @Test func answerTextIsIndentedWithSortedKeysAndPlainSlashes() throws {
        let answer: JSONValue = .object(["b": .int(2), "a": .string("x/y")])
        let text = MessagingAnswerFormat.displayText(answer)
        #expect(text.contains("x/y") && !text.contains("\\/"))
        let first = try #require(text.range(of: "\"a\"")?.lowerBound)
        let second = try #require(text.range(of: "\"b\"")?.lowerBound)
        #expect(first < second && text.contains("\n"))
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) == answer)
    }

    @Test func answerTextMasksValuesUnderSecretKeysOnly() throws {
        let answer: JSONValue = .object([
            "platforms": .array([
                .object([
                    "id": .string("telegram"),
                    "env": .object(["TELEGRAM_BOT_TOKEN": .string("123:abc"), "LOG_LEVEL": .string("debug")]),
                    "webhook_secret": .string("s3cret"),
                    "tokens": .array([.string("42")]),
                    "author": .string("jt"),
                ])
            ]),
            "api_key": .null,
        ])
        let text = MessagingAnswerFormat.displayText(answer)
        #expect(!text.contains("123:abc") && !text.contains("s3cret") && !text.contains("42"))
        let shown = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(
            shown
                == .object([
                    "platforms": .array([
                        .object([
                            "id": .string("telegram"),
                            "env": .object(["TELEGRAM_BOT_TOKEN": .string("••••"), "LOG_LEVEL": .string("debug")]),
                            "webhook_secret": .string("••••"),
                            "tokens": .array([.string("••••")]),
                            "author": .string("jt"),
                        ])
                    ]),
                    "api_key": .null,
                ]))
    }
}
