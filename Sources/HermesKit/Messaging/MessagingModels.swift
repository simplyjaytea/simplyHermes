import Foundation

// Request bodies for the messaging, pairing and webhook calls, as the API schema describes them. Optional fields
// stay nil and are left out of the JSON, so the server applies its own defaults. The schema does not describe any
// answer of these calls, so the calls that read an answer return ``JSONValue`` as the server sent it.

/// `PUT /api/messaging/platforms/{platform_id}`. Turns a platform on or off and sets or clears its settings.
public struct MessagingPlatformUpdate: Sendable, Equatable, Codable {
    /// Turns the platform on or off. Nil leaves it as it is.
    public var enabled: Bool?
    /// Settings to set, such as bot tokens. Values are secrets: never log them.
    public var env: [String: String]
    /// Setting names to remove.
    public var clearEnv: [String]
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates a platform update. Only the fields that are set are sent.
    public init(
        enabled: Bool? = nil, env: [String: String] = [:], clearEnv: [String] = [], profile: String? = nil
    ) {
        self.enabled = enabled
        self.env = env
        self.clearEnv = clearEnv
        self.profile = profile
    }
}

/// `POST /api/messaging/telegram/onboarding/start`.
public struct MessagingTelegramStart: Sendable, Equatable, Codable {
    /// The name the bot is given, when set.
    public var botName: String?

    /// Creates a start request.
    public init(botName: String? = nil) {
        self.botName = botName
    }
}

/// `POST /api/messaging/telegram/onboarding/{pairing_id}/apply`.
public struct MessagingTelegramApply: Sendable, Equatable, Codable {
    /// Telegram user ids allowed to talk to the bot.
    public var allowedUserIds: [String]
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates an apply request.
    public init(allowedUserIds: [String], profile: String? = nil) {
        self.allowedUserIds = allowedUserIds
        self.profile = profile
    }
}

/// `POST /api/messaging/whatsapp/onboarding/start`. The schema's defaults are `bot` and an empty string.
public struct MessagingWhatsAppStart: Sendable, Equatable, Codable {
    /// Pairing mode, such as `bot`. Nil keeps the server default.
    public var mode: String?
    /// The allowed users, as the server takes them. Nil keeps the server default.
    public var allowedUsers: String?
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates a start request.
    public init(mode: String? = nil, allowedUsers: String? = nil, profile: String? = nil) {
        self.mode = mode
        self.allowedUsers = allowedUsers
        self.profile = profile
    }
}

/// `POST /api/messaging/whatsapp/onboarding/{pairing_id}/apply`.
public struct MessagingWhatsAppApply: Sendable, Equatable, Codable {
    /// Pairing mode, such as `bot`. Nil keeps what the pairing has.
    public var mode: String?
    /// The allowed users, as the server takes them. Nil keeps what the pairing has.
    public var allowedUsers: String?
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates an apply request.
    public init(mode: String? = nil, allowedUsers: String? = nil, profile: String? = nil) {
        self.mode = mode
        self.allowedUsers = allowedUsers
        self.profile = profile
    }
}

/// `POST /api/pairing/approve`. Approves a pending request by the code the bot sent, or by its request id.
public struct PairingApprove: Sendable, Equatable, Codable {
    /// Platform the request came from, such as `telegram`.
    public var platform: String
    /// The pairing code. Empty when the request id is used instead.
    public var code: String
    /// Id of the pending request. Empty when the code is used instead.
    public var requestId: String
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates an approval.
    public init(platform: String, code: String = "", requestId: String = "", profile: String? = nil) {
        self.platform = platform
        self.code = code
        self.requestId = requestId
        self.profile = profile
    }
}

/// `POST /api/pairing/revoke`. Takes a user's access back on one platform.
public struct PairingRevoke: Sendable, Equatable, Codable {
    /// Platform the user is on, such as `telegram`.
    public var platform: String
    /// The user's id on that platform.
    public var userId: String
    /// Profile the change applies to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates a revoke request.
    public init(platform: String, userId: String, profile: String? = nil) {
        self.platform = platform
        self.userId = userId
        self.profile = profile
    }
}

/// `POST /api/webhooks`. Only `name` is required. The other fields take the server's defaults when they are empty.
public struct WebhookCreate: Sendable, Equatable, Codable {
    /// Webhook name. Later calls to change or delete it use this name.
    public var name: String
    /// What the webhook is for, when set.
    public var description: String?
    /// Event names. Empty takes the server default.
    public var events: [String]
    /// Prompt for the agent, when set.
    public var prompt: String?
    /// Script to run, when set.
    public var script: String?
    /// Skills to load. Empty takes the server default.
    public var skills: [String]
    /// Delivery target. The server default is `log`.
    public var deliver: String
    /// True when the webhook only delivers and does not run the agent.
    public var deliverOnly: Bool
    /// Chat id for delivery, when set.
    public var deliverChatId: String?
    /// Secret for the webhook. A secret: enter it in a secure field, and never show or log it.
    public var secret: String?
    /// Profile the webhook belongs to. ``RESTClient`` fills it from its own profile when nil.
    public var profile: String?

    /// Creates a webhook definition.
    public init(
        name: String, description: String? = nil, events: [String] = [], prompt: String? = nil,
        script: String? = nil, skills: [String] = [], deliver: String = "log", deliverOnly: Bool = false,
        deliverChatId: String? = nil, secret: String? = nil, profile: String? = nil
    ) {
        self.name = name
        self.description = description
        self.events = events
        self.prompt = prompt
        self.script = script
        self.skills = skills
        self.deliver = deliver
        self.deliverOnly = deliverOnly
        self.deliverChatId = deliverChatId
        self.secret = secret
        self.profile = profile
    }
}

/// `PUT /api/webhooks/{name}/enabled`. A disabled webhook stays on disk, and the server rejects its events.
public struct WebhookEnabledToggle: Sendable, Equatable, Codable {
    /// True to enable the webhook.
    public var enabled: Bool

    /// Creates a toggle.
    public init(enabled: Bool) {
        self.enabled = enabled
    }
}
