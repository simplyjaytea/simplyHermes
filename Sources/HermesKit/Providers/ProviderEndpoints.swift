import Foundation

/// Percent-encodes one path segment, so an id with a slash or a space stays one segment.
private func providerSegment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

// Rules for this file. A call the testbed recorded returns a typed answer only for the fields its recording shows
// (see Fixtures/rest). A write the testbed did not record reads only the HTTP status, and the caller reads the list
// again afterwards. An answer with no recording comes back as JSONValue and is shown as received, never read by field.

// MARK: - Custom endpoints

extension RESTClient {
    /// `GET /api/providers/custom-endpoints`. Recorded, so the answer is typed.
    public func customEndpoints() async throws -> ProviderCustomEndpointList {
        try await get("/api/providers/custom-endpoints")
    }

    /// `POST /api/providers/custom-endpoints`: creates or updates an endpoint. Recorded for name, base URL, model and
    /// `discover_models`. The other body fields are not recorded and need a real server. Status-only.
    public func saveCustomEndpoint(_ draft: ProviderCustomEndpointDraft) async throws {
        let _: HTTPResponse = try await send("POST", "/api/providers/custom-endpoints", body: draft)
    }

    /// `POST /api/providers/custom-endpoints/validate`: probes the endpoint's model list with the draft. Recorded for the
    /// same body as the save. The answer is kept as received. Not scoped by profile: the contract has no parameter for it.
    public func validateCustomEndpoint(_ draft: ProviderCustomEndpointDraft) async throws -> JSONValue {
        try await send(
            "POST", "/api/providers/custom-endpoints/validate", body: draft, scoped: false, as: JSONValue.self)
    }

    /// `POST /api/providers/custom-endpoints/{endpoint_id}/activate`: makes the endpoint the provider for new chats.
    /// Not recorded on the testbed. Status-only.
    public func activateCustomEndpoint(id: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/providers/custom-endpoints/" + providerSegment(id) + "/activate", encodedPath: true)
    }

    /// `DELETE /api/providers/custom-endpoints/{endpoint_id}`: removes the endpoint from the config. Recorded. Status-only.
    /// Confirm with the user first.
    public func deleteCustomEndpoint(id: String) async throws {
        let _: HTTPResponse = try await send(
            "DELETE", "/api/providers/custom-endpoints/" + providerSegment(id), encodedPath: true)
    }
}

// MARK: - Provider keys and OAuth

extension RESTClient {
    /// `POST /api/providers/validate`: probes a provider key. Not recorded, so the answer is not read. Status-only.
    /// Not scoped by profile.
    public func validateProviderKey(_ write: ApiKeyWrite) async throws {
        let _: HTTPResponse = try await send("POST", "/api/providers/validate", body: write, scoped: false)
    }

    /// `GET /api/providers/oauth`: every OAuth-capable provider with its status. Recorded; kept as received.
    public func oauthProviders() async throws -> JSONValue {
        try await get("/api/providers/oauth", as: JSONValue.self)
    }

    /// `POST /api/providers/oauth/{provider_id}/start`: begins a login. Not recorded (the testbed never runs OAuth), so
    /// the session it opens cannot be read here. Status-only.
    public func startOAuthLogin(provider: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/providers/oauth/" + providerSegment(provider) + "/start", encodedPath: true)
    }

    /// `GET /api/providers/oauth/{provider_id}/poll/{session_id}`. Not recorded; kept as received.
    public func pollOAuthLogin(provider: String, session: String) async throws -> JSONValue {
        try await get(
            "/api/providers/oauth/" + providerSegment(provider) + "/poll/" + providerSegment(session),
            encodedPath: true,
            as: JSONValue.self)
    }

    /// `POST /api/providers/oauth/{provider_id}/submit`: sends the code a PKCE flow asks for. Not recorded. Status-only.
    public func submitOAuthCode(provider: String, _ submit: ProviderOAuthSubmit) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/providers/oauth/" + providerSegment(provider) + "/submit", body: submit, encodedPath: true)
    }

    /// `DELETE /api/providers/oauth/sessions/{session_id}`: cancels a pending login. Not recorded. Status-only.
    public func cancelOAuthLogin(session: String) async throws {
        let _: HTTPResponse = try await send(
            "DELETE", "/api/providers/oauth/sessions/" + providerSegment(session), encodedPath: true)
    }

    /// `DELETE /api/providers/oauth/{provider_id}`: disconnects an OAuth provider. Not recorded. Status-only. Confirm
    /// with the user first.
    public func disconnectOAuthProvider(_ provider: String) async throws {
        let _: HTTPResponse = try await send(
            "DELETE", "/api/providers/oauth/" + providerSegment(provider), encodedPath: true)
    }
}

// MARK: - API keys (the env store)

extension RESTClient {
    /// `GET /api/env`: every variable, keyed by its name. Recorded, so the answer is typed. Values are never typed.
    public func envVars() async throws -> [String: ApiKeyEntry] {
        try await get("/api/env")
    }

    /// `PUT /api/env`: sets one variable. Recorded with `key` and `value`. Status-only.
    public func setApiKey(_ write: ApiKeyWrite) async throws {
        let _: HTTPResponse = try await send("PUT", "/api/env", body: write)
    }

    /// `DELETE /api/env`: removes one variable. Recorded. Status-only. Confirm with the user first.
    public func deleteApiKey(named key: String) async throws {
        let _: HTTPResponse = try await send("DELETE", "/api/env", body: ApiKeyNameRequest(key: key))
    }

    /// `POST /api/env/reveal`: the value of one variable. Not recorded, so the answer is kept as received. The server
    /// rate-limits it, so call it only when the user taps to show a value, never on load.
    public func revealApiKey(named key: String) async throws -> JSONValue {
        try await send("POST", "/api/env/reveal", body: ApiKeyNameRequest(key: key), as: JSONValue.self)
    }
}

// MARK: - Credentials pool

extension RESTClient {
    /// `GET /api/credentials/pool`: the pooled keys, grouped by provider. Recorded, so the answer is typed.
    public func credentialPool() async throws -> CredentialPoolList {
        try await get("/api/credentials/pool")
    }

    /// `POST /api/credentials/pool`: adds a key to the pool. Recorded. Status-only.
    public func addCredential(_ draft: CredentialPoolDraft) async throws {
        let _: HTTPResponse = try await send("POST", "/api/credentials/pool", body: draft)
    }

    /// `DELETE /api/credentials/pool/{provider}/{index}`. `index` is the entry's `index` from the list, numbered from 1.
    /// The testbed recorded only the 404 for a missing index, so a successful removal is not recorded. Status-only.
    /// The server removes the entry from its backing source too. Confirm with the user first.
    public func removeCredential(provider: String, index: Int) async throws {
        let _: HTTPResponse = try await send(
            "DELETE", "/api/credentials/pool/" + providerSegment(provider) + "/" + String(index), encodedPath: true)
    }
}
