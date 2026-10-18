import Foundation

extension RESTClient {
    /// `GET /api/model/options` with the picker's flags. `includeUnconfigured` adds providers without credentials, with
    /// `authenticated` false. `refresh` busts the server's model-id cache.
    public func providerCatalog(refresh: Bool = false, includeUnconfigured: Bool = false) async throws -> ModelOptions {
        var query: [URLQueryItem] = []
        if refresh { query.append(URLQueryItem(name: "refresh", value: "true")) }
        if includeUnconfigured { query.append(URLQueryItem(name: "include_unconfigured", value: "true")) }
        return try await get("/api/model/options", query: query)
    }

    /// `POST /api/model/set`: assigns a provider and model to the main slot or an auxiliary task.
    public func assignModel(_ assignment: ModelDefaultsAssignment) async throws {
        let _: HTTPResponse = try await send("POST", "/api/model/set", body: assignment)
    }

    /// `GET /api/model/auxiliary`: one row per auxiliary task, and the main slot.
    public func auxiliaryModels() async throws -> ModelDefaultsAuxiliary {
        try await get("/api/model/auxiliary")
    }

    /// `GET /api/model/recommended-default?provider=`: the model a fresh sign-in for `provider` should land on.
    public func recommendedModel(provider: String) async throws -> ModelDefaultsRecommendation {
        try await get("/api/model/recommended-default", query: [URLQueryItem(name: "provider", value: provider)])
    }

    /// `GET /api/model/moa`. The contract does not type the answer, so it comes back as it came.
    public func moaModels() async throws -> JSONValue {
        try await get("/api/model/moa", as: JSONValue.self)
    }

    /// `PUT /api/model/moa`. The server replaces the whole Mixture-of-Agents document, and a key left out falls back to
    /// its default. Read the document with ``moaModels()``, change it, and send all of it back.
    public func setMoaModels(_ document: JSONValue) async throws {
        let _: HTTPResponse = try await send("PUT", "/api/model/moa", body: document)
    }
}
