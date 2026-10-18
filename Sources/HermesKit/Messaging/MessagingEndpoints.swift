import Foundation

/// Percent-encodes each part of a path, so an id with a slash or a space stays one segment.
private func messagingPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

// Writes read only the HTTP status: a 2xx ends the call, and the answer body is not decoded. The testbed recorded no
// success answer for them, so every write the testbed did not exercise says "needs real server [JT]".

// MARK: - Messaging platforms

extension RESTClient {
    /// `GET /api/messaging/platforms`. Typed from Fixtures/rest/GET_api_messaging_platforms.json (200, at e3dc403).
    public func messagingPlatforms() async throws -> MessagingPlatformList {
        try await get("/api/messaging/platforms")
    }

    /// `PUT /api/messaging/platforms/{platform_id}`. Turns a platform on or off and sets or clears its settings.
    /// Only the HTTP status is read. Not exercised by the testbed: needs real server [JT].
    public func updateMessagingPlatform(id: String, _ update: MessagingPlatformUpdate) async throws {
        var body = update
        body.profile = body.profile ?? profile
        _ = try await send("PUT", "/api/messaging/platforms/" + messagingPath(id), body: body)
    }

    /// `POST /api/messaging/platforms/{platform_id}/test`. Only the HTTP status is read. Not exercised by the testbed:
    /// needs real server [JT].
    public func testMessagingPlatform(id: String) async throws {
        _ = try await send("POST", "/api/messaging/platforms/" + messagingPath(id, "test"))
    }
}

// MARK: - Telegram onboarding

extension RESTClient {
    /// `POST /api/messaging/telegram/onboarding/start`. Only the HTTP status is read: no pairing id is recorded, so
    /// none is taken from the answer. Not exercised by the testbed: needs real server [JT].
    public func startTelegramOnboarding(_ start: MessagingTelegramStart) async throws {
        _ = try await send("POST", "/api/messaging/telegram/onboarding/start", body: start)
    }

    /// `GET /api/messaging/telegram/onboarding/{pairing_id}`: the pairing's current state. No answer is recorded, and
    /// the testbed had no pairing id, so the answer comes back as the server sent it. Needs real server [JT].
    public func telegramOnboarding(pairingID: String) async throws -> JSONValue {
        try await get("/api/messaging/telegram/onboarding/" + messagingPath(pairingID))
    }

    /// `DELETE /api/messaging/telegram/onboarding/{pairing_id}`: cancels the pairing. Only the HTTP status is read.
    /// Needs real server [JT].
    public func cancelTelegramOnboarding(pairingID: String) async throws {
        _ = try await send("DELETE", "/api/messaging/telegram/onboarding/" + messagingPath(pairingID))
    }

    /// `POST /api/messaging/telegram/onboarding/{pairing_id}/apply`: finishes the pairing with the allowed user ids.
    /// Only the HTTP status is read. Needs real server [JT].
    public func applyTelegramOnboarding(pairingID: String, _ apply: MessagingTelegramApply) async throws {
        var body = apply
        body.profile = body.profile ?? profile
        _ = try await send(
            "POST", "/api/messaging/telegram/onboarding/" + messagingPath(pairingID, "apply"), body: body)
    }
}

// MARK: - WhatsApp onboarding

extension RESTClient {
    /// `POST /api/messaging/whatsapp/onboarding/start`. Only the HTTP status is read: no pairing id is recorded, so
    /// none is taken from the answer. Not exercised by the testbed: needs real server [JT].
    public func startWhatsAppOnboarding(_ start: MessagingWhatsAppStart) async throws {
        var body = start
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/messaging/whatsapp/onboarding/start", body: body)
    }

    /// `GET /api/messaging/whatsapp/onboarding/{pairing_id}`: the pairing's current state. No answer is recorded, and
    /// the testbed had no pairing id, so the answer comes back as the server sent it. Needs real server [JT].
    public func whatsAppOnboarding(pairingID: String) async throws -> JSONValue {
        try await get("/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID))
    }

    /// `DELETE /api/messaging/whatsapp/onboarding/{pairing_id}`: cancels the pairing. Only the HTTP status is read.
    /// Needs real server [JT].
    public func cancelWhatsAppOnboarding(pairingID: String) async throws {
        _ = try await send("DELETE", "/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID))
    }

    /// `POST /api/messaging/whatsapp/onboarding/{pairing_id}/apply`: finishes the pairing. Only the HTTP status is read.
    /// Needs real server [JT].
    public func applyWhatsAppOnboarding(pairingID: String, _ apply: MessagingWhatsAppApply) async throws {
        var body = apply
        body.profile = body.profile ?? profile
        _ = try await send(
            "POST", "/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID, "apply"), body: body)
    }
}

// MARK: - Pairing requests

extension RESTClient {
    /// `GET /api/pairing`. Typed from Fixtures/rest/GET_api_pairing.json (200, at e3dc403): the counts of its lists.
    public func pairingRequests() async throws -> PairingRequestList {
        try await get("/api/pairing")
    }

    /// `POST /api/pairing/approve`: approves a pending request by its code or its request id. Only the HTTP status is
    /// read. Not exercised by the testbed: needs real server [JT].
    public func approvePairing(_ approve: PairingApprove) async throws {
        var body = approve
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/pairing/approve", body: body)
    }

    /// `POST /api/pairing/revoke`: takes a user's access back on one platform. Only the HTTP status is read.
    /// Not exercised by the testbed: needs real server [JT].
    public func revokePairing(_ revoke: PairingRevoke) async throws {
        var body = revoke
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/pairing/revoke", body: body)
    }

    /// `POST /api/pairing/clear-pending`: clears the pending pairing requests. Only the HTTP status is read.
    /// Not exercised by the testbed: needs real server [JT].
    public func clearPendingPairing() async throws {
        _ = try await send("POST", "/api/pairing/clear-pending")
    }
}

// MARK: - Webhooks

extension RESTClient {
    /// `GET /api/webhooks`. Typed from Fixtures/rest/GET_api_webhooks.json and GET_api_webhooks.seeded.json
    /// (both 200, at e3dc403).
    public func webhooks() async throws -> WebhookList {
        try await get("/api/webhooks")
    }

    /// `POST /api/webhooks`: creates a webhook. The testbed's create answers 400
    /// (Fixtures/rest/POST_api_webhooks.json), so no success answer is recorded. Only the HTTP status is read.
    /// Needs real server [JT].
    public func createWebhook(_ create: WebhookCreate) async throws {
        var body = create
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/webhooks", body: body)
    }

    /// `POST /api/webhooks/enable`: enables webhooks on the server. Only the HTTP status is read.
    /// Not exercised by the testbed: needs real server [JT].
    public func enableWebhooks() async throws {
        _ = try await send("POST", "/api/webhooks/enable")
    }

    /// `DELETE /api/webhooks/{name}`: deletes the webhook. The testbed recorded only the 404 for a missing name
    /// (Fixtures/rest/DELETE_api_webhooks_recorder-hook.json). Only the HTTP status is read. Needs real server [JT].
    public func deleteWebhook(name: String) async throws {
        _ = try await send("DELETE", "/api/webhooks/" + messagingPath(name))
    }

    /// `PUT /api/webhooks/{name}/enabled`: enables or disables one webhook without deleting it. Only the HTTP status is
    /// read. Not exercised by the testbed: needs real server [JT].
    public func setWebhookEnabled(name: String, _ enabled: Bool) async throws {
        _ = try await send(
            "PUT", "/api/webhooks/" + messagingPath(name, "enabled"), body: WebhookEnabledToggle(enabled: enabled))
    }
}
