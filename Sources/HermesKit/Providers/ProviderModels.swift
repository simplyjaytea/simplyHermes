import Foundation

/// Values of `api_mode` for a custom endpoint. The field is a plain string, so the server may send or accept other
/// values. The testbed recorded only an empty `api_mode`, so these values need a real server to confirm.
public enum ProviderAPIModes {
    /// Chat completions.
    public static let chatCompletions = "chat_completions"
    /// Codex responses.
    public static let codexResponses = "codex_responses"
    /// Anthropic messages.
    public static let anthropicMessages = "anthropic_messages"
    /// The values the picker offers, in order.
    public static let options = [chatCompletions, codexResponses, anthropicMessages]
}

/// One custom endpoint in `GET /api/providers/custom-endpoints` (`endpoints[]`).
/// Fields are the ones Fixtures/rest/GET_api_providers_custom-endpoints.seeded.json shows. The API key preview is not typed.
public struct ProviderCustomEndpoint: Sendable, Equatable, Codable, Identifiable {
    /// Endpoint id, such as the name it was saved under.
    public var id: String
    /// Name to show.
    public var name: String
    /// OpenAI-compatible base URL.
    public var baseUrl: String
    /// Model the endpoint uses.
    public var model: String?
    /// Model ids the endpoint lists.
    public var models: [String]?
    /// API mode in use, empty when automatic.
    public var apiMode: String?
    /// True when the server asks the endpoint for its model list.
    public var discoverModels: Bool?
    /// True when an API key is stored for the endpoint.
    public var hasApiKey: Bool?
    /// True for the endpoint in use.
    public var isCurrent: Bool?
    /// Where the endpoint is defined, such as `providers` or `direct-config`.
    public var source: String?
}

/// `GET /api/providers/custom-endpoints`. The answer's `current` block is not typed: no screen reads it.
/// Shape from Fixtures/rest/GET_api_providers_custom-endpoints.seeded.json.
public struct ProviderCustomEndpointList: Sendable, Equatable, Codable {
    /// Every custom endpoint the server knows.
    public var endpoints: [ProviderCustomEndpoint]
}

/// Body of `POST /api/providers/custom-endpoints` and `POST /api/providers/custom-endpoints/validate`.
/// Nil optionals are left out. The testbed recorded only `name`, `base_url`, `model` and `discover_models`
/// (Fixtures/rest/POST_api_providers_custom-endpoints.json); the other fields need a real server.
public struct ProviderCustomEndpointDraft: Sendable, Equatable, Codable {
    /// Name to show.
    public var name: String
    /// OpenAI-compatible base URL, such as `http://192.168.1.20:8000/v1`.
    public var baseUrl: String
    /// Model id to use.
    public var model: String
    /// API key for the endpoint. Secret: never log it.
    public var apiKey: String?
    /// How requests are shaped, one of ``ProviderAPIModes``. Nil leaves the choice to the server.
    public var apiMode: String?
    /// Context window in tokens, when the server should not detect it.
    public var contextLength: Int?
    /// Ask the endpoint for its model list.
    public var discoverModels: Bool
    /// Make this endpoint the default provider when it saves. Nil leaves the server default, which is off.
    public var makeDefault: Bool?

    /// Creates a draft. Discovery is on by default, as the server defaults it.
    public init(
        name: String, baseUrl: String, model: String, apiKey: String? = nil, apiMode: String? = nil,
        contextLength: Int? = nil, discoverModels: Bool = true, makeDefault: Bool? = nil
    ) {
        self.name = name
        self.baseUrl = baseUrl
        self.model = model
        self.apiKey = apiKey
        self.apiMode = apiMode
        self.contextLength = contextLength
        self.discoverModels = discoverModels
        self.makeDefault = makeDefault
    }
}

/// Body of `PUT /api/env` (`EnvVarUpdate`): sets one environment variable, such as a provider key. Recorded with `key`
/// and `value` only (Fixtures/rest/PUT_api_env.json). The `profile` field is not sent: the REST client adds it.
public struct ApiKeyWrite: Sendable, Equatable, Codable {
    /// Variable name, such as `OPENROUTER_API_KEY`.
    public var key: String
    /// The value. Secret: never log it or show it in previews.
    public var value: String

    /// Creates a write.
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Body of `DELETE /api/env` and `POST /api/env/reveal` (`EnvVarDelete`, `EnvVarReveal`). The delete is recorded
/// (Fixtures/rest/DELETE_api_env.json); the reveal is not.
public struct ApiKeyNameRequest: Sendable, Equatable, Codable {
    /// Variable name.
    public var key: String

    /// Creates a request.
    public init(key: String) {
        self.key = key
    }
}

/// One variable in `GET /api/env`, keyed by its name in the answer. Only the fields the screens use are typed; they
/// come from Fixtures/rest/GET_api_env.seeded.json. The value is never typed: it is shown only through the reveal call.
public struct ApiKeyEntry: Sendable, Equatable, Codable {
    /// True when the variable has a value on the server.
    public var isSet: Bool?
    /// True when the variable holds a secret.
    public var isPassword: Bool?
    /// Provider slug the variable belongs to, when any.
    public var provider: String?
    /// Name of that provider, to show.
    public var providerLabel: String?
}

/// Body of `POST /api/credentials/pool` (`CredentialPoolAdd`). Recorded with `provider`, `api_key` and `label`
/// (Fixtures/rest/POST_api_credentials_pool.json).
public struct CredentialPoolDraft: Sendable, Equatable, Codable {
    /// Provider slug, such as `openrouter`.
    public var provider: String
    /// The key to pool. Secret: never log it.
    public var apiKey: String
    /// Name to show in the pool, when given.
    public var label: String?

    /// Creates a draft.
    public init(provider: String, apiKey: String, label: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.label = label
    }
}

/// `GET /api/credentials/pool`: the pooled keys, grouped by provider. Shape from
/// Fixtures/rest/GET_api_credentials_pool.seeded.json. An empty pool is Fixtures/rest/GET_api_credentials_pool.json.
public struct CredentialPoolList: Sendable, Equatable, Codable {
    /// One group per provider with pooled keys.
    public var providers: [CredentialPoolProvider]
}

/// One provider's group in the credentials pool.
public struct CredentialPoolProvider: Sendable, Equatable, Codable, Identifiable {
    /// Provider slug.
    public var provider: String
    /// The pooled keys of this provider, in pool order.
    public var entries: [CredentialPoolEntry]

    /// Identity for lists.
    public var id: String { provider }
}

/// One pooled key. The token itself is never typed: the answer carries only a redacted preview.
public struct CredentialPoolEntry: Sendable, Equatable, Codable, Identifiable {
    /// Entry id the pool assigns.
    public var id: String
    /// Position in the pool, numbered from 1. Removal uses it: the testbed's 404 for index 0 shows 1 is the first.
    public var index: Int
    /// Name the key was saved under.
    public var label: String?
    /// Credential type, such as `api_key`.
    public var authType: String?
    /// Where the key came from, such as `manual`.
    public var source: String?
    /// Order the pool tries keys in.
    public var priority: Int?
    /// Requests this key has served.
    public var requestCount: Int?
}

/// Body of `POST /api/providers/oauth/{provider_id}/submit` (`OAuthSubmitBody`). Not recorded: the testbed never ran an
/// OAuth login, so the field names come from the contract alone.
public struct ProviderOAuthSubmit: Sendable, Equatable, Codable {
    /// The login session the code belongs to.
    public var sessionId: String
    /// The code the provider showed.
    public var code: String

    /// Creates a submission.
    public init(sessionId: String, code: String) {
        self.sessionId = sessionId
        self.code = code
    }
}
