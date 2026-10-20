import Foundation
import HermesKit
import Testing

/// Each test checks the method, path, query and JSON body the facade sends, and the answer it returns. Writes are
/// checked by their status alone: the transport answers with a body that the call does not read.
@Suite struct MessagingEndpointTests {
    /// The JSON body a request carried.
    private func body(_ request: HTTPRequest?) throws -> JSONValue {
        let data = try #require(request?.body)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    @Test func platformsReadUpdateAndTest() async throws {
        let http = FakeHTTP()
        http.enqueue(200, MessagingRecorded.platforms)
        http.enqueue(200, "")
        http.enqueue(200, "")
        let client = makeClient(http, profile: "ops")
        let answer = try await client.messagingPlatforms()
        #expect(answer.platforms.contains { $0.id == "first" })
        let update = MessagingPlatformUpdate(
            enabled: true, env: ["TELEGRAM_BOT_TOKEN": "123:abc"], clearEnv: ["OLD_KEY"])
        try await client.updateMessagingPlatform(id: "telegram", update)
        try await client.testMessagingPlatform(id: "telegram")
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "PUT", "POST"])
        #expect(requests[0].url.path == "/api/messaging/platforms" && requests[0].url.query == "profile=ops")
        #expect(requests[1].url.path == "/api/messaging/platforms/telegram")
        #expect(requests[2].url.path == "/api/messaging/platforms/telegram/test")
        #expect(
            try body(requests[1])
                == .object([
                    "enabled": .bool(true), "env": .object(["TELEGRAM_BOT_TOKEN": .string("123:abc")]),
                    "clear_env": .array([.string("OLD_KEY")]), "profile": .string("ops"),
                ]))
        #expect(requests[2].body == nil)
    }

    @Test func platformUpdateLeavesUnsetFieldsOut() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        let client = makeClient(http)
        try await client.updateMessagingPlatform(id: "whatsapp", MessagingPlatformUpdate())
        #expect(try body(http.requests.first) == .object(["env": .object([:]), "clear_env": .array([])]))
    }

    @Test func platformIdIsOnePathSegment() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        let client = makeClient(http)
        try await client.updateMessagingPlatform(id: "a/b c", MessagingPlatformUpdate(enabled: false))
        let request = try #require(http.requests.first)
        #expect(request.url.path == "/api/messaging/platforms/a%2Fb%20c")
        #expect(request.url.query == nil, "no profile is set, so no query is sent")
    }

    @Test func telegramOnboardingStartStatusApplyAndCancel() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        http.enqueue(200, #"{"status":"pending"}"#)
        http.enqueue(200, "")
        http.enqueue(200, "")
        let client = makeClient(http, profile: "ops")
        try await client.startTelegramOnboarding(MessagingTelegramStart(botName: "simply bot"))
        let status = try await client.telegramOnboarding(pairingID: "p 1/2")
        #expect(status == .object(["status": .string("pending")]))
        try await client.applyTelegramOnboarding(
            pairingID: "p 1/2", MessagingTelegramApply(allowedUserIds: ["11", "12"]))
        try await client.cancelTelegramOnboarding(pairingID: "p 1/2")
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "GET", "POST", "DELETE"])
        #expect(requests[0].url.path == "/api/messaging/telegram/onboarding/start")
        #expect(requests[1].url.path == "/api/messaging/telegram/onboarding/p%201%2F2")
        #expect(requests[2].url.path == "/api/messaging/telegram/onboarding/p%201%2F2/apply")
        #expect(requests[3].url.path == "/api/messaging/telegram/onboarding/p%201%2F2")
        #expect(requests.allSatisfy { $0.url.query == "profile=ops" })
        #expect(try body(requests[0]) == .object(["bot_name": .string("simply bot")]))
        #expect(
            try body(requests[2])
                == .object(["allowed_user_ids": .array([.string("11"), .string("12")]), "profile": .string("ops")]))
    }

    @Test func whatsAppOnboardingStartStatusApplyAndCancel() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        http.enqueue(200, #"{"status":"pending"}"#)
        http.enqueue(200, "")
        http.enqueue(200, "")
        let client = makeClient(http, profile: "ops")
        try await client.startWhatsAppOnboarding(MessagingWhatsAppStart(mode: "bot", allowedUsers: ""))
        _ = try await client.whatsAppOnboarding(pairingID: "w1")
        try await client.applyWhatsAppOnboarding(pairingID: "w1", MessagingWhatsAppApply(mode: "bot"))
        try await client.cancelWhatsAppOnboarding(pairingID: "w1")
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "GET", "POST", "DELETE"])
        #expect(requests[0].url.path == "/api/messaging/whatsapp/onboarding/start")
        #expect(requests[1].url.path == "/api/messaging/whatsapp/onboarding/w1")
        #expect(requests[2].url.path == "/api/messaging/whatsapp/onboarding/w1/apply")
        #expect(requests[3].url.path == "/api/messaging/whatsapp/onboarding/w1")
        #expect(
            try body(requests[0])
                == .object(["mode": .string("bot"), "allowed_users": .string(""), "profile": .string("ops")]))
        #expect(try body(requests[2]) == .object(["mode": .string("bot"), "profile": .string("ops")]))
    }

    @Test func pairingRequestsApproveRevokeAndClear() async throws {
        let http = FakeHTTP()
        http.enqueue(200, MessagingRecorded.pairing)
        http.enqueue(200, "")
        http.enqueue(200, "")
        http.enqueue(200, "")
        let client = makeClient(http, profile: "ops")
        let pending = try await client.pairingRequests()
        #expect(pending.pendingCount == 0 && pending.approvedCount == 0)
        try await client.approvePairing(PairingApprove(platform: "telegram", code: "ABC123"))
        try await client.revokePairing(PairingRevoke(platform: "telegram", userId: "42"))
        try await client.clearPendingPairing()
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "POST", "POST", "POST"])
        #expect(requests[0].url.path == "/api/pairing" && requests[0].url.query == "profile=ops")
        #expect(requests[1].url.path == "/api/pairing/approve")
        #expect(requests[2].url.path == "/api/pairing/revoke")
        #expect(requests[3].url.path == "/api/pairing/clear-pending")
        #expect(
            try body(requests[1])
                == .object([
                    "platform": .string("telegram"), "code": .string("ABC123"), "request_id": .string(""),
                    "profile": .string("ops"),
                ]))
        #expect(
            try body(requests[2])
                == .object(["platform": .string("telegram"), "user_id": .string("42"), "profile": .string("ops")]))
        #expect(requests[3].body == nil)
    }

    @Test func explicitBodyProfileWins() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        let client = makeClient(http, profile: "ops")
        try await client.revokePairing(PairingRevoke(platform: "telegram", userId: "7", profile: "bot2"))
        #expect(try body(http.requests.first)["profile"] == .string("bot2"))
    }

    @Test func webhooksListCreateEnableDeleteAndToggle() async throws {
        let http = FakeHTTP()
        http.enqueue(200, MessagingRecorded.webhooks)
        http.enqueue(200, "")
        http.enqueue(200, "")
        http.enqueue(200, "")
        http.enqueue(200, "")
        let client = makeClient(http)
        let list = try await client.webhooks()
        #expect(list.baseUrl == "http://localhost:8644" && !list.enabled && list.subscriptionCount == 0)
        try await client.createWebhook(WebhookCreate(name: "deploy", events: ["push"], deliverOnly: true))
        try await client.enableWebhooks()
        try await client.setWebhookEnabled(name: "ops/alerts v2", false)
        try await client.deleteWebhook(name: "ops/alerts v2")
        let requests = http.requests
        #expect(requests.map(\.method) == ["GET", "POST", "POST", "PUT", "DELETE"])
        #expect(requests[0].url.path == "/api/webhooks" && requests[0].url.query == nil)
        #expect(requests[2].url.path == "/api/webhooks/enable")
        #expect(requests[2].body == nil)
        #expect(requests[3].url.path == "/api/webhooks/ops%2Falerts%20v2/enabled")
        #expect(try body(requests[3]) == .object(["enabled": .bool(false)]))
        #expect(requests[4].url.path == "/api/webhooks/ops%2Falerts%20v2")
        #expect(requests[4].body == nil)
        let created = try body(requests[1])
        #expect(created["name"] == .string("deploy") && created["events"] == .array([.string("push")]))
        #expect(created["deliver"] == .string("log") && created["deliver_only"] == .bool(true))
        #expect(created["skills"] == .array([]) && created["secret"] == nil)
    }

    @Test func webhookSecretIsSentOnlyWhenSet() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "")
        let client = makeClient(http)
        let create = WebhookCreate(name: "signed", deliverChatId: "42", secret: "s3cret")
        try await client.createWebhook(create)
        let sent = try body(http.requests.first)
        #expect(sent["secret"] == .string("s3cret") && sent["deliver_chat_id"] == .string("42"))
        #expect(sent["profile"] == nil, "no profile is set, so the body carries none")
    }

    @Test func webhookCreateRefusalSurfacesTheDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(400, MessagingRecorded.webhookCreateRefused)
        let client = makeClient(http)
        await #expect(
            throws: RESTError.http(
                status: 400, detail: "Webhook platform is not enabled. Enable it from the Webhooks page first.")
        ) {
            try await client.createWebhook(WebhookCreate(name: "recorder-hook"))
        }
    }

    @Test func serverRefusalsSurfaceAsRESTErrors() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"Not Found"}"#)
        let client = makeClient(http)
        await #expect(throws: RESTError.http(status: 404, detail: "Not Found")) {
            try await client.deleteWebhook(name: "gone")
        }
    }
}
