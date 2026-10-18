import Foundation

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
