import Foundation

/// The answer of `PUT /api/tools/toolsets/{name}`.
public struct ToolsetToggleResult: Sendable, Equatable, Codable {
    /// True when the change was saved.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// Configuration platform the switch wrote to, such as `cli`.
    public var platform: String?
    /// The state now saved.
    public var enabled: Bool?
    /// The provider whose install the switch started in the background, when one was missing.
    public var postSetupStarted: String?
}

/// `GET /api/tools/toolsets/{name}/config`: the provider picker and the key status of one toolset.
public struct SkillToolsetConfig: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String
    /// False when the toolset has no provider picker.
    public var hasCategory: Bool?
    /// The picker rows, in order.
    public var providers: [ToolsetProviderRow]?
    /// Name of the provider in use.
    public var activeProvider: String?
}

/// One row of a toolset's provider picker.
public struct ToolsetProviderRow: Sendable, Equatable, Codable, Identifiable {
    /// Provider name, the value `PUT .../provider` takes.
    public var name: String
    /// Short label, such as `Recommended`.
    public var badge: String?
    /// One-line tag.
    public var tag: String?
    /// Environment variables the provider reads.
    public var envVars: [SkillToolsetEnvVar]?
    /// Post-setup key that installs what the provider needs, when any.
    public var postSetup: String?
    /// True when a Nous Portal sign-in is needed.
    public var requiresNousAuth: Bool?
    /// True for the provider in use.
    public var isActive: Bool?
    /// Readiness as the server words it.
    public var status: String?

    /// Identity for lists.
    public var id: String { name }
}

/// One environment variable a provider reads.
public struct SkillToolsetEnvVar: Sendable, Equatable, Codable, Identifiable {
    /// Variable name, such as `FIRECRAWL_API_KEY`.
    public var key: String
    /// Prompt to show above the field.
    public var prompt: String?
    /// Where to get the value.
    public var url: String?
    /// True when a value is saved. The value itself is never sent.
    public var isSet: Bool?

    /// Identity for lists.
    public var id: String { key }
}

/// `GET /api/tools/toolsets/{name}/models`: the model catalog of a toolset backend, such as image generation.
public struct SkillToolsetModelCatalog: Sendable, Equatable, Codable {
    /// Toolset name.
    public var name: String
    /// False when the backend has no model catalog.
    public var hasModels: Bool?
    /// The picker row the catalog belongs to.
    public var provider: String?
    /// The backend plugin that serves the models.
    public var plugin: String?
    /// The models, in order.
    public var models: [ToolsetModelOption]?
    /// The model in use.
    public var current: String?
    /// The model used when none is chosen.
    public var defaultModel: String?

    enum CodingKeys: String, CodingKey {
        case name, hasModels, provider, plugin, models, current
        case defaultModel = "default"
    }
}

/// One model in a toolset's catalog.
public struct ToolsetModelOption: Sendable, Equatable, Codable, Identifiable {
    /// Model id, the value `PUT .../model` takes.
    public var id: String
    /// Name to show.
    public var display: String?
    /// Speed label such as `fast`.
    public var speed: String?
    /// What the model is good at.
    public var strengths: String?
    /// Price label.
    public var price: String?
}

/// The answer of `PUT /api/tools/toolsets/{name}/model`.
public struct ToolsetModelSelection: Sendable, Equatable, Codable {
    /// True when the model was saved.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// The model now saved.
    public var model: String?
    /// The backend plugin that serves it.
    public var plugin: String?
}

/// The answer of `PUT /api/tools/toolsets/{name}/provider`. `needsNousAuth` is set when a managed row is not entitled.
public struct ToolsetProviderSelection: Sendable, Equatable, Codable {
    /// True when the provider was saved.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// The provider now saved.
    public var provider: String?
    /// `search` or `extract`, for the web toolset.
    public var capability: String?
    /// True when the managed provider needs a Nous Portal entitlement before it works.
    public var needsNousAuth: Bool?
    /// The managed feature that needs it.
    public var feature: String?
}

/// The answer of `PUT /api/tools/toolsets/{name}/env`. Blank values are skipped, so they keep what is saved.
public struct ToolsetEnvSaved: Sendable, Equatable, Codable {
    /// True when the call succeeded.
    public var ok: Bool?
    /// Toolset name.
    public var name: String?
    /// Variables written.
    public var saved: [String]?
    /// Variables left as they were.
    public var skipped: [String]?
    /// Whether each variable of the toolset's providers has a value now.
    public var isSet: [String: Bool]?
}
