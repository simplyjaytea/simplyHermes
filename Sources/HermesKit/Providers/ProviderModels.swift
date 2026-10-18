import Foundation

/// API mode of a custom endpoint (`api_mode` in `CustomEndpointUpdate`). Nil means automatic.
public enum ProviderAPIMode: String, Sendable, Equatable, Codable, CaseIterable {
    case chatCompletions = "chat_completions"
    case codexResponses = "codex_responses"
    case anthropicMessages = "anthropic_messages"
}

/// One routing row a gateway may advertise for a model (`CustomEndpointModelDetail`).
public struct ProviderCustomEndpointModelDetail: Sendable, Equatable, Codable {
    /// Model id as the endpoint lists it.
    public var id: String
    /// The model the id routes to, when it differs.
    public var canonicalModel: String?
    /// Reasoning effort the id implies, when any.
    public var reasoningEffort: String?

    /// Creates a value.
    public init(id: String, canonicalModel: String? = nil, reasoningEffort: String? = nil) {
        self.id = id
        self.canonicalModel = canonicalModel
        self.reasoningEffort = reasoningEffort
    }
}

/// Body of `POST /api/providers/custom-endpoints` and `POST /api/providers/custom-endpoints/validate`
/// (`CustomEndpointUpdate`). Optional fields that are nil are left out of the request.
public struct ProviderCustomEndpointDraft: Sendable, Equatable, Codable {
    /// Endpoint id. Empty on create, so the server assigns one.
    public var id: String
    /// Name to show.
    public var name: String
    /// OpenAI-compatible base URL, such as `http://192.168.1.20:8000/v1`.
    public var baseUrl: String
    /// Model id to use.
    public var model: String
    /// API key for the endpoint. Secret: never log it.
    public var apiKey: String?
    /// How requests are shaped. Nil leaves the choice to the server.
    public var apiMode: ProviderAPIMode?
    /// Context window in tokens, when the server should not detect it.
    public var contextLength: Int?
    /// Ask the endpoint for its model list.
    public var discoverModels: Bool
    /// Make this endpoint the default provider when it saves.
    public var makeDefault: Bool
    /// Model ids to offer, when known.
    public var models: [String]?
    /// Routing rows for model ids, when known.
    public var modelDetails: [ProviderCustomEndpointModelDetail]?

    /// Creates a draft. Defaults match the server: discover models on, do not make it the default.
    public init(
        id: String = "", name: String, baseUrl: String, model: String, apiKey: String? = nil,
        apiMode: ProviderAPIMode? = nil, contextLength: Int? = nil, discoverModels: Bool = true,
        makeDefault: Bool = false, models: [String]? = nil, modelDetails: [ProviderCustomEndpointModelDetail]? = nil
    ) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.model = model
        self.apiKey = apiKey
        self.apiMode = apiMode
        self.contextLength = contextLength
        self.discoverModels = discoverModels
        self.makeDefault = makeDefault
        self.models = models
        self.modelDetails = modelDetails
    }
}

/// Body of `PUT /api/env` (`EnvVarUpdate`): sets one environment variable, such as a provider key.
/// The `profile` field is not sent: the REST client already adds it as the query parameter.
public struct ApiKeyWrite: Sendable, Equatable, Codable {
    /// Variable name, such as `OPENROUTER_API_KEY`.
    public var key: String
    /// The value. Secret: never log it or show it in previews.
    public var value: String
    /// True when the write sets up a provider, not only the variable.
    public var providerSetup: Bool

    /// Creates a write.
    public init(key: String, value: String, providerSetup: Bool = false) {
        self.key = key
        self.value = value
        self.providerSetup = providerSetup
    }
}

/// Body of `DELETE /api/env` and `POST /api/env/reveal` (`EnvVarDelete`, `EnvVarReveal`).
public struct ApiKeyNameRequest: Sendable, Equatable, Codable {
    /// Variable name.
    public var key: String

    /// Creates a request.
    public init(key: String) {
        self.key = key
    }
}

/// Body of `POST /api/credentials/pool` (`CredentialPoolAdd`).
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

/// Body of `POST /api/providers/oauth/{provider_id}/submit` (`OAuthSubmitBody`).
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

/// Answer of `POST /api/providers/validate`: `{ok, reachable, message}`.
///
/// `ok` true means the provider accepted the key. `ok` false with `reachable` true means the key was refused. `reachable`
/// false means the probe could not run, so the caller may save with a warning.
public struct ProviderCredentialCheck: Sendable, Equatable, Codable {
    /// True when the provider accepted the key.
    public var ok: Bool
    /// False when the provider could not be reached.
    public var reachable: Bool?
    /// Text the server wants shown.
    public var message: String?

    /// Creates a value.
    public init(ok: Bool, reachable: Bool? = nil, message: String? = nil) {
        self.ok = ok
        self.reachable = reachable
        self.message = message
    }
}
