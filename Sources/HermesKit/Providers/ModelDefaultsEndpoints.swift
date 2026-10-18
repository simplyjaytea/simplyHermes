import Foundation

extension RESTClient {
    /// `GET /api/model/options` with the picker's flags. Recorded for the plain call; `includeUnconfigured` adds providers
    /// without credentials, with `authenticated` false, and is not recorded. `refresh` busts the server's model-id cache.
    public func providerCatalog(refresh: Bool = false, includeUnconfigured: Bool = false) async throws -> ModelOptions {
        var query: [URLQueryItem] = []
        if refresh { query.append(URLQueryItem(name: "refresh", value: "true")) }
        if includeUnconfigured { query.append(URLQueryItem(name: "include_unconfigured", value: "true")) }
        return try await get("/api/model/options", query: query)
    }

    /// `POST /api/model/set`: assigns a provider and model to the main slot or an auxiliary task. Not recorded on the
    /// testbed. Status-only: the caller reads the model again afterwards and shows what the server now holds.
    public func assignModel(_ assignment: ModelDefaultsAssignment) async throws {
        let _: HTTPResponse = try await send("POST", "/api/model/set", body: assignment)
    }

    /// `GET /api/model/auxiliary`: one row per auxiliary task, and the main slot. Recorded.
    public func auxiliaryModels() async throws -> ModelDefaultsAuxiliary {
        try await get("/api/model/auxiliary")
    }

    /// `GET /api/model/recommended-default?provider=`: the model a fresh sign-in for `provider` should land on. Recorded
    /// without the query; the query variant is not recorded.
    public func recommendedModel(provider: String) async throws -> ModelDefaultsRecommendation {
        try await get("/api/model/recommended-default", query: [URLQueryItem(name: "provider", value: provider)])
    }

    /// `GET /api/model/moa`. Recorded; the contract does not type the answer, so it comes back as it came.
    public func moaModels() async throws -> JSONValue {
        try await get("/api/model/moa", as: JSONValue.self)
    }

    /// `PUT /api/model/moa`. Not recorded on the testbed. The server replaces the whole Mixture-of-Agents document, and a
    /// key left out falls back to its default. Read the document with ``moaModels()``, change it, and send all of it
    /// back. Status-only.
    public func setMoaModels(_ document: JSONValue) async throws {
        let _: HTTPResponse = try await send("PUT", "/api/model/moa", body: document)
    }
}
