import Foundation

// Answers of the messaging, pairing and webhook calls. Each type decodes only fields that a recorded testbed answer
// shows. The files are under Fixtures/rest at commit e3dc403, and each doc comment names the file it is typed from.
// Values vary between testbed runs (ids, timestamps, network answers), so a field is typed by its JSON type only:
// string fields are not restricted to sample values, and no list is assumed to come in any order. A field the
// recording leaves null in every row has no type evidence yet, so it is not decoded. Unknown keys are ignored.

/// `GET /api/messaging/platforms`. Field evidence: Fixtures/rest/GET_api_messaging_platforms.json (200, at e3dc403).
public struct MessagingPlatformList: Sendable, Equatable, Decodable {
    /// The settings file the server writes, such as `/data/hermes/.env`.
    public let envPath: String
    /// The command that starts the gateway.
    public let gatewayStartCommand: String
    /// The platforms the server lists.
    public let platforms: [MessagingPlatform]
}

/// One platform of ``MessagingPlatformList``. Field evidence: Fixtures/rest/GET_api_messaging_platforms.json (200, at
/// e3dc403), `platforms[]`. Not decoded: `error_code`, `error_message`, `home_channel`, `ingress_url` and `updated_at`.
/// The recording has each of them as null in every row, so no JSON type is known for them yet.
public struct MessagingPlatform: Sendable, Equatable, Decodable {
    /// The id the platform's paths use. Free text from the server.
    public let id: String
    /// The name to show.
    public let name: String
    /// What the platform is, in a sentence.
    public let description: String
    /// The platform's setup page.
    public let docsUrl: String
    /// The state the server reports. Free text from the server, not an enum.
    public let state: String
    /// True when the settings the platform needs are set.
    public let configured: Bool
    /// True when the platform is turned on.
    public let enabled: Bool
    /// True when the gateway runs the platform.
    public let gatewayRunning: Bool
    /// The settings the platform takes. May be empty.
    public let envVars: [MessagingEnvVar]
    /// WhatsApp's setup state. Present only on some rows: the WhatsApp row in the recording.
    public let whatsappSetup: MessagingWhatsAppSetup?
}

/// One setting of a platform, in ``MessagingPlatform/envVars``. Field evidence:
/// Fixtures/rest/GET_api_messaging_platforms.json (200, at e3dc403), `platforms[].env_vars[]`.
/// Not decoded: `value`, which can hold a secret (the recorder hides it only under secret key names), and
/// `redacted_value`, which the recording has as null in every row.
public struct MessagingEnvVar: Sendable, Equatable, Decodable {
    /// The setting's name on the server.
    public let key: String
    /// The label to show.
    public let prompt: String
    /// What the setting is for.
    public let description: String
    /// Extra help text. May be empty.
    public let help: String
    /// Where to find the value, when the server gives a link.
    public let url: String?
    /// True when the setting is required.
    public let required: Bool
    /// True for an advanced setting.
    public let advanced: Bool
    /// True when the value is a comma-separated list.
    public let isList: Bool
    /// True for a secret. The screens never show its value.
    public let isPassword: Bool
    /// True when the server has a value for the setting.
    public let isSet: Bool
}

/// WhatsApp's setup state, in ``MessagingPlatform/whatsappSetup``. Field evidence:
/// Fixtures/rest/GET_api_messaging_platforms.json (200, at e3dc403), the WhatsApp row's `whatsapp_setup`.
public struct MessagingWhatsAppSetup: Sendable, Equatable, Decodable {
    /// True when allowed users are set.
    public let allowedUsersSet: Bool
    /// True when a home channel is set.
    public let homeChannelSet: Bool
    /// The pairing mode the server reports. Free text from the server.
    public let mode: String
}

/// `GET /api/pairing`. Field evidence: Fixtures/rest/GET_api_pairing.json (200, at e3dc403): `approved` and `pending` are
/// arrays. Both are empty in the recording, so the items have no field evidence. Only their counts are kept.
public struct PairingRequestList: Sendable, Equatable, Decodable {
    /// The number of requests that wait for approval.
    public let pendingCount: Int
    /// The number of approved users.
    public let approvedCount: Int

    /// The two arrays as sent. The items are counted, not read.
    private struct Wire: Decodable {
        let approved: [JSONValue]
        let pending: [JSONValue]
    }

    /// Counts the items of both arrays.
    public init(from decoder: any Decoder) throws {
        let wire = try Wire(from: decoder)
        pendingCount = wire.pending.count
        approvedCount = wire.approved.count
    }
}

/// `GET /api/webhooks`. Field evidence: Fixtures/rest/GET_api_webhooks.json and Fixtures/rest/GET_api_webhooks.seeded.json
/// (both 200, at e3dc403): `base_url` (string), `enabled` (boolean) and `subscriptions` (array). The recorded
/// subscriptions are empty, so their items have no field evidence. Only their count is kept.
public struct WebhookList: Sendable, Equatable, Decodable {
    /// Where the webhook server listens. Free text from the server.
    public let baseUrl: String
    /// True when webhooks are turned on.
    public let enabled: Bool
    /// The number of subscriptions on the server.
    public let subscriptionCount: Int

    /// The fields as sent. The subscriptions are counted, not read.
    private struct Wire: Decodable {
        let baseUrl: String
        let enabled: Bool
        let subscriptions: [JSONValue]
    }

    /// Reads the three fields and counts the subscriptions.
    public init(from decoder: any Decoder) throws {
        let wire = try Wire(from: decoder)
        baseUrl = wire.baseUrl
        enabled = wire.enabled
        subscriptionCount = wire.subscriptions.count
    }
}

/// One row of a messaging screen: a title and the status under it.
public struct MessagingStatusLine: Sendable, Equatable {
    /// The row's title.
    public let title: String
    /// The status under the title.
    public let detail: String

    /// Creates a row.
    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

extension MessagingPlatformList {
    /// One row per platform, as the server listed them: its name, then its state and whether it is set up.
    public var statusLines: [MessagingStatusLine] {
        platforms.map { platform -> MessagingStatusLine in
            let setUp = platform.configured ? "set up" : "not set up"
            return MessagingStatusLine(title: platform.name, detail: "\(platform.state), \(setUp)")
        }
    }
}

extension PairingRequestList {
    /// How many requests wait and how many users are approved. The items are not shown: their fields are not recorded.
    public var statusLines: [MessagingStatusLine] {
        [
            MessagingStatusLine(title: "Waiting for approval", detail: "\(pendingCount)"),
            MessagingStatusLine(title: "Approved users", detail: "\(approvedCount)"),
        ]
    }
}

extension WebhookList {
    /// Whether webhooks are on, where they listen, and how many subscriptions there are. Status only.
    public var statusLines: [MessagingStatusLine] {
        [
            MessagingStatusLine(title: "Webhooks", detail: enabled ? "On" : "Off"),
            MessagingStatusLine(title: "Base URL", detail: baseUrl),
            MessagingStatusLine(title: "Subscriptions", detail: "\(subscriptionCount)"),
        ]
    }
}
