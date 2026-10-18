import Foundation

/// Percent-encodes each part of a path, so an id with a slash or a space stays one segment.
private func messagingPath(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

// MARK: - Messaging platforms

extension RESTClient {
    /// `GET /api/messaging/platforms`. The schema does not describe the answer, so it comes back as the server sent it.
    public func messagingPlatforms() async throws -> JSONValue {
        try await get("/api/messaging/platforms")
    }

    /// `PUT /api/messaging/platforms/{platform_id}`. Enables or disables a platform and sets or clears its settings.
    public func updateMessagingPlatform(id: String, _ update: MessagingPlatformUpdate) async throws {
        var body = update
        body.profile = body.profile ?? profile
        _ = try await send("PUT", "/api/messaging/platforms/" + messagingPath(id), body: body)
    }

    /// `POST /api/messaging/platforms/{platform_id}/test`. The answer is returned as the server sent it.
    public func testMessagingPlatform(id: String) async throws -> JSONValue {
        try await send("POST", "/api/messaging/platforms/" + messagingPath(id, "test"))
    }
}

// MARK: - Telegram onboarding

extension RESTClient {
    /// `POST /api/messaging/telegram/onboarding/start`. Starts a pairing. The schema does not describe the answer.
    public func startTelegramOnboarding(_ start: MessagingTelegramStart) async throws -> JSONValue {
        try await send("POST", "/api/messaging/telegram/onboarding/start", body: start)
    }

    /// `GET /api/messaging/telegram/onboarding/{pairing_id}`: the pairing's current state.
    public func telegramOnboarding(pairingID: String) async throws -> JSONValue {
        try await get("/api/messaging/telegram/onboarding/" + messagingPath(pairingID))
    }

    /// `DELETE /api/messaging/telegram/onboarding/{pairing_id}`: cancels the pairing.
    public func cancelTelegramOnboarding(pairingID: String) async throws {
        _ = try await send("DELETE", "/api/messaging/telegram/onboarding/" + messagingPath(pairingID))
    }

    /// `POST /api/messaging/telegram/onboarding/{pairing_id}/apply`: finishes the pairing with the allowed user ids.
    public func applyTelegramOnboarding(pairingID: String, _ apply: MessagingTelegramApply) async throws -> JSONValue {
        var body = apply
        body.profile = body.profile ?? profile
        return try await send(
            "POST", "/api/messaging/telegram/onboarding/" + messagingPath(pairingID, "apply"), body: body)
    }
}

// MARK: - WhatsApp onboarding

extension RESTClient {
    /// `POST /api/messaging/whatsapp/onboarding/start`. Starts a pairing. The schema does not describe the answer.
    public func startWhatsAppOnboarding(_ start: MessagingWhatsAppStart) async throws -> JSONValue {
        var body = start
        body.profile = body.profile ?? profile
        return try await send("POST", "/api/messaging/whatsapp/onboarding/start", body: body)
    }

    /// `GET /api/messaging/whatsapp/onboarding/{pairing_id}`: the pairing's current state.
    public func whatsAppOnboarding(pairingID: String) async throws -> JSONValue {
        try await get("/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID))
    }

    /// `DELETE /api/messaging/whatsapp/onboarding/{pairing_id}`: cancels the pairing.
    public func cancelWhatsAppOnboarding(pairingID: String) async throws {
        _ = try await send("DELETE", "/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID))
    }

    /// `POST /api/messaging/whatsapp/onboarding/{pairing_id}/apply`: finishes the pairing.
    public func applyWhatsAppOnboarding(pairingID: String, _ apply: MessagingWhatsAppApply) async throws -> JSONValue {
        var body = apply
        body.profile = body.profile ?? profile
        return try await send(
            "POST", "/api/messaging/whatsapp/onboarding/" + messagingPath(pairingID, "apply"), body: body)
    }
}

// MARK: - Pairing requests

extension RESTClient {
    /// `GET /api/pairing`. The answer is returned as the server sent it.
    public func pairingRequests() async throws -> JSONValue {
        try await get("/api/pairing")
    }

    /// `POST /api/pairing/approve`: approves a pending request by its code or its request id.
    public func approvePairing(_ approve: PairingApprove) async throws {
        var body = approve
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/pairing/approve", body: body)
    }

    /// `POST /api/pairing/revoke`: takes a user's access back on one platform.
    public func revokePairing(_ revoke: PairingRevoke) async throws {
        var body = revoke
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/pairing/revoke", body: body)
    }

    /// `POST /api/pairing/clear-pending`: clears the pending pairing requests.
    public func clearPendingPairing() async throws {
        _ = try await send("POST", "/api/pairing/clear-pending")
    }
}

// MARK: - Webhooks

extension RESTClient {
    /// `GET /api/webhooks`. The answer is returned as the server sent it.
    public func webhooks() async throws -> JSONValue {
        try await get("/api/webhooks")
    }

    /// `POST /api/webhooks`: creates a webhook.
    public func createWebhook(_ create: WebhookCreate) async throws {
        var body = create
        body.profile = body.profile ?? profile
        _ = try await send("POST", "/api/webhooks", body: body)
    }

    /// `POST /api/webhooks/enable`: enables webhooks on the server.
    public func enableWebhooks() async throws {
        _ = try await send("POST", "/api/webhooks/enable")
    }

    /// `DELETE /api/webhooks/{name}`: deletes the webhook.
    public func deleteWebhook(name: String) async throws {
        _ = try await send("DELETE", "/api/webhooks/" + messagingPath(name))
    }

    /// `PUT /api/webhooks/{name}/enabled`: enables or disables one webhook without deleting it.
    public func setWebhookEnabled(name: String, _ enabled: Bool) async throws {
        _ = try await send(
            "PUT", "/api/webhooks/" + messagingPath(name, "enabled"), body: WebhookEnabledToggle(enabled: enabled))
    }
}
