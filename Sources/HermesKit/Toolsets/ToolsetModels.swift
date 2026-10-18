import Foundation

/// `PUT /api/tools/toolsets/{name}`: the answer to a switch. ``postSetupStarted`` names a background install the
/// server started because the toolset needs one.
public struct ToolsetToggleResult: Sendable, Equatable, Codable {
    /// True when the change was saved.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// Platform whose toolset list changed.
    public var platform: String?
    /// The state now stored.
    public var enabled: Bool?
    /// Setup key of the background install, when one started.
    public var postSetupStarted: String?
}

/// `GET /api/tools/toolsets/{name}/config`: the provider rows and key status of a toolset's config panel.
public struct ToolsetConfig: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String?
    /// False when the toolset has no provider category, so there is nothing to configure here.
    public var hasCategory: Bool?
    /// Provider rows, in the server's order.
    public var providers: [ToolsetProvider]?
    /// Name of the provider in use.
    public var activeProvider: String?
}

/// One provider row of a toolset's config.
public struct ToolsetProvider: Sendable, Equatable, Codable, Identifiable {
    /// Provider name. Pass it back to choose the provider.
    public var name: String
    /// Short label such as `free` or `paid`.
    public var badge: String?
    /// Longer tag.
    public var tag: String?
    /// Keys the provider reads. Values are never sent; ``ToolsetEnvVar/isSet`` says whether one is stored.
    public var envVars: [ToolsetEnvVar]?
    /// Setup key for `POST …/post-setup`, when the provider has an install step.
    public var postSetup: String?
    /// True when the provider needs a Nous Portal subscription.
    public var requiresNousAuth: Bool?
    /// Subscription feature the provider needs, if any.
    public var managedNousFeature: String?
    /// True for the provider in use.
    public var isActive: Bool?
    /// `ready`, `needs_keys`, `needs_auth` or `needs_setup`.
    public var status: String?
    /// For the web toolset: the capabilities the backend has, such as `search` and `extract`.
    public var capabilities: [String]?

    /// Identity for lists.
    public var id: String { name }
}

/// One API key a provider reads. The stored value is never sent to the app.
public struct ToolsetEnvVar: Sendable, Equatable, Codable, Identifiable {
    /// Variable name, such as `FIRECRAWL_API_KEY`.
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

/// Body of `PUT /api/tools/toolsets/{name}/env`. A blank value leaves the stored key unchanged.
public struct ToolsetEnvUpdate: Sendable, Equatable, Codable {
    /// Key to value. Send only the keys the user filled in.
    public var env: [String: String]

    /// Creates a body.
    public init(env: [String: String]) {
        self.env = env
    }
}

/// The answer to a key save: which keys were stored, which were blank, and whether each key is set now.
public struct ToolsetEnvResult: Sendable, Equatable, Codable {
    /// True when the save was accepted.
    public var ok: Bool?
    /// Keys that were stored.
    public var saved: [String]?
    /// Keys left unchanged because the value was blank.
    public var skipped: [String]?
    /// Every key of the toolset to whether it is set now.
    public var isSet: [String: Bool]?
}

/// `GET /api/tools/toolsets/{name}/models`: the models a media backend offers.
public struct ToolsetModelCatalog: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String?
    /// False when the toolset has no model list.
    public var hasModels: Bool?
    /// Provider row the list belongs to.
    public var provider: String?
    /// Backend plugin that supplies the list.
    public var plugin: String?
    /// The models.
    public var models: [ToolsetModelOption]?
    /// Id of the model in use.
    public var current: String?
    /// Id the backend uses when none is chosen.
    public var defaultModel: String?

    enum CodingKeys: String, CodingKey {
        case name, hasModels, provider, plugin, models, current
        case defaultModel = "default"
    }
}

/// One model of a media backend.
public struct ToolsetModelOption: Sendable, Equatable, Codable, Identifiable {
    /// Model id. Pass it back to choose the model.
    public var id: String
    /// Name to show.
    public var display: String?
    /// Speed note.
    public var speed: String?
    /// What the model is good at.
    public var strengths: String?
    /// Price note.
    public var price: String?
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
    /// Provider name from ``ToolsetConfig/providers``.
    public var provider: String
    /// `search` or `extract`. Only the web toolset takes one. Nil sets both.
    public var capability: String?

    /// Creates a body.
    public init(provider: String, capability: String? = nil) {
        self.provider = provider
        self.capability = capability
    }
}

/// The answer to a provider choice. ``needsNousAuth`` means the row is a Nous subscription row that is not
/// active yet, because the app cannot sign in to the Portal.
public struct ToolsetProviderResult: Sendable, Equatable, Codable {
    /// True when the choice was saved.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// Provider chosen.
    public var provider: String?
    /// Capability the choice applies to, if one was given.
    public var capability: String?
    /// True when the provider needs a Nous Portal entitlement first.
    public var needsNousAuth: Bool?
    /// Feature that is missing, with ``needsNousAuth``.
    public var feature: String?
}

/// Body of `POST /api/tools/toolsets/{name}/post-setup`.
public struct ToolsetPostSetup: Sendable, Equatable, Codable {
    /// Setup key from ``ToolsetProvider/postSetup``.
    public var key: String

    /// Creates a body.
    public init(key: String) {
        self.key = key
    }
}
