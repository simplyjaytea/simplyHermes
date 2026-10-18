import Foundation

/// Percent-encodes one path segment, so an id with a slash or a space stays one segment.
private func providerSegment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

// Answers the API contract does not type (its 200 schema is empty) come back as ``JSONValue``, as they came.

// MARK: - Custom endpoints

extension RESTClient {
    /// `GET /api/providers/custom-endpoints`.
    public func customEndpoints() async throws -> JSONValue {
        try await get("/api/providers/custom-endpoints", as: JSONValue.self)
    }

    /// `POST /api/providers/custom-endpoints`: creates or updates an endpoint. `makeDefault` also makes it the default.
    public func saveCustomEndpoint(_ draft: ProviderCustomEndpointDraft) async throws -> JSONValue {
        try await send("POST", "/api/providers/custom-endpoints", body: draft, as: JSONValue.self)
    }

    /// `POST /api/providers/custom-endpoints/validate`: probes the endpoint's `/models` URL with the draft. Not scoped
    /// by profile, because the contract has no profile parameter for it.
    public func validateCustomEndpoint(_ draft: ProviderCustomEndpointDraft) async throws -> JSONValue {
        try await send(
            "POST", "/api/providers/custom-endpoints/validate", body: draft, scoped: false, as: JSONValue.self)
    }

    /// `POST /api/providers/custom-endpoints/{endpoint_id}/activate`: makes the endpoint the default provider.
    public func activateCustomEndpoint(id: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/providers/custom-endpoints/" + providerSegment(id) + "/activate")
    }

    /// `DELETE /api/providers/custom-endpoints/{endpoint_id}`. Removes the endpoint from the config. Confirm first.
    public func deleteCustomEndpoint(id: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/providers/custom-endpoints/" + providerSegment(id))
    }
}

// MARK: - Provider keys and OAuth

extension RESTClient {
    /// `POST /api/providers/validate`: probes a provider key before it is saved. Not scoped by profile.
    public func validateProviderKey(_ write: ApiKeyWrite) async throws -> ProviderCredentialCheck {
        try await send("POST", "/api/providers/validate", body: write, scoped: false)
    }

    /// `GET /api/providers/oauth`: every OAuth-capable provider with its status.
    public func oauthProviders() async throws -> JSONValue {
        try await get("/api/providers/oauth", as: JSONValue.self)
    }

    /// `POST /api/providers/oauth/{provider_id}/start`: begins a login. Poll the session the answer names.
    public func startOAuthLogin(provider: String) async throws -> JSONValue {
        try await send("POST", "/api/providers/oauth/" + providerSegment(provider) + "/start", as: JSONValue.self)
    }

    /// `GET /api/providers/oauth/{provider_id}/poll/{session_id}`: progress, in the worker-updated `status`.
    public func pollOAuthLogin(provider: String, session: String) async throws -> JSONValue {
        try await get(
            "/api/providers/oauth/" + providerSegment(provider) + "/poll/" + providerSegment(session),
            as: JSONValue.self)
    }

    /// `POST /api/providers/oauth/{provider_id}/submit`: sends the code a PKCE flow asks for.
    public func submitOAuthCode(provider: String, _ submit: ProviderOAuthSubmit) async throws -> JSONValue {
        try await send(
            "POST", "/api/providers/oauth/" + providerSegment(provider) + "/submit", body: submit, as: JSONValue.self)
    }

    /// `DELETE /api/providers/oauth/sessions/{session_id}`: cancels a pending login.
    public func cancelOAuthLogin(session: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/providers/oauth/sessions/" + providerSegment(session))
    }

    /// `DELETE /api/providers/oauth/{provider_id}`: disconnects an OAuth provider. Confirm first.
    public func disconnectOAuthProvider(_ provider: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/providers/oauth/" + providerSegment(provider))
    }
}

// MARK: - API keys (the env store)

extension RESTClient {
    /// `GET /api/env`: the env store. Values may be redacted; the answer comes back as it came.
    public func envVars() async throws -> JSONValue {
        try await get("/api/env", as: JSONValue.self)
    }

    /// `PUT /api/env`: sets one variable.
    public func setApiKey(_ write: ApiKeyWrite) async throws {
        let _: HTTPResponse = try await send("PUT", "/api/env", body: write)
    }

    /// `DELETE /api/env`: removes one variable. Confirm first.
    public func deleteApiKey(named key: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/env", body: ApiKeyNameRequest(key: key))
    }

    /// `POST /api/env/reveal`: the real value of one variable. The server rate-limits it, so call it only when the
    /// user asks to see the value, never on load.
    public func revealApiKey(named key: String) async throws -> JSONValue {
        try await send("POST", "/api/env/reveal", body: ApiKeyNameRequest(key: key), as: JSONValue.self)
    }
}

// MARK: - Credentials pool

extension RESTClient {
    /// `GET /api/credentials/pool`: the pooled keys, numbered from 1 in the answer.
    public func credentialPool() async throws -> JSONValue {
        try await get("/api/credentials/pool", as: JSONValue.self)
    }

    /// `POST /api/credentials/pool`: adds a key to the pool.
    public func addCredential(_ draft: CredentialPoolDraft) async throws -> JSONValue {
        try await send("POST", "/api/credentials/pool", body: draft, as: JSONValue.self)
    }

    /// `DELETE /api/credentials/pool/{provider}/{index}`. `index` is 1-based, as the pool numbers its entries. The
    /// server removes the entry from its backing source too. Confirm first.
    public func removeCredential(provider: String, index: Int) async throws {
        let _: HTTPResponse = try await send(
            "DELETE", "/api/credentials/pool/" + providerSegment(provider) + "/" + String(index))
    }
}
