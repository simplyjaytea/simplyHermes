import Foundation

/// `GET /api/tools/toolsets/{name}/config`: the provider rows of a toolset's config panel. Typed from
/// `Fixtures/rest/GET_api_tools_toolsets_web_config.json`, the web toolset. `active_provider` is null in that answer,
/// so it has no type here.
public struct ToolsetConfig: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String?
    /// True when the toolset has a provider category.
    public var hasCategory: Bool?
    /// Provider rows, in the server's order.
    public var providers: [ToolsetProvider]?
    /// Extract backend in use. A plain string, since its value varies between runs.
    public var activeExtractBackend: String?
    /// Search backend in use. A plain string, since its value varies between runs.
    public var activeSearchBackend: String?
}

/// One provider row of a toolset's config, typed from `Fixtures/rest/GET_api_tools_toolsets_web_config.json`.
public struct ToolsetProvider: Sendable, Equatable, Codable, Identifiable {
    /// Provider name. Pass it back to choose the provider.
    public var name: String
    /// Short label, such as `subscription`.
    public var badge: String?
    /// Longer tag.
    public var tag: String?
    /// Keys the provider reads. Values are never sent; ``ToolsetEnvVar/isSet`` says whether one is stored.
    public var envVars: [ToolsetEnvVar]?
    /// Setup key for the post-setup call, when the provider has an install step.
    public var postSetup: String?
    /// True when the provider needs a Nous Portal subscription.
    public var requiresNousAuth: Bool?
    /// Subscription feature the provider needs, if any.
    public var managedNousFeature: String?
    /// True for the provider in use.
    public var isActive: Bool?
    /// Setup state, such as `needs_keys`.
    public var status: String?
    /// For the web toolset: the capabilities the backend has, such as `search` and `extract`.
    public var capabilities: [String]?

    /// Identity for lists.
    public var id: String { name }
}

/// One API key a provider reads. The stored value is never sent to the app. Typed from
/// `Fixtures/rest/GET_api_tools_toolsets_web_config.json`. Its `default` is null in that answer, so it has no type here.
public struct ToolsetEnvVar: Sendable, Equatable, Codable, Identifiable {
    /// Variable name, such as `FIRECRAWL_API_URL`.
    public var key: String
    /// Label to show for the value.
    public var prompt: String?
    /// Where to get the key.
    public var url: String?
    /// True when a value is stored.
    public var isSet: Bool?

    /// Identity for lists.
    public var id: String { key }
}

/// `GET /api/tools/toolsets/{name}/models`: whether a toolset has a model list. Typed from
/// `Fixtures/rest/GET_api_tools_toolsets_web_models.json`. In that answer `models`, `current` and `default` are empty or
/// null, so they have no type here.
public struct ToolsetModelCatalog: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String?
    /// False when the toolset has no model list.
    public var hasModels: Bool?
}

/// Body of `PUT /api/tools/toolsets/{name}/env`. A blank value leaves the stored key unchanged.
public struct ToolsetEnvUpdate: Sendable, Equatable, Codable {
    /// Key to value. Send only the keys the user filled in.
    public var env: [String: String]

    /// Creates a body.
    public init(env: [String: String]) {
        self.env = env
    }
}

/// Body of `PUT /api/tools/toolsets/{name}/model`. Without ``provider`` the active row is used.
public struct ToolsetModelSelect: Sendable, Equatable, Codable {
    /// Model id from the catalog.
    public var model: String
    /// Provider row, when it is not the active one.
    public var provider: String?

    /// Creates a body.
    public init(model: String, provider: String? = nil) {
        self.model = model
        self.provider = provider
    }
}

/// Body of `PUT /api/tools/toolsets/{name}/provider`.
public struct ToolsetProviderSelect: Sendable, Equatable, Codable {
    /// Provider name, as the server lists it.
    public var provider: String
    /// `search` or `extract`. Only the web toolset takes one. Nil sets both.
    public var capability: String?

    /// Creates a body.
    public init(provider: String, capability: String? = nil) {
        self.provider = provider
        self.capability = capability
    }
}

/// Body of `POST /api/tools/toolsets/{name}/post-setup`.
public struct ToolsetPostSetup: Sendable, Equatable, Codable {
    /// Setup key the server gives for a provider's install step.
    public var key: String

    /// Creates a body.
    public init(key: String) {
        self.key = key
    }
}
