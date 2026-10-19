import Foundation

// The session calls the list, the export and the `@session:` links make (WP-40). Each id is percent-encoded as one
// path segment. A profile is sent as the `profile` query, so the call names its owner whatever the client's scope is.

extension RESTClient {
    /// `GET /api/sessions/{id}/export`. The bytes come back as the server sent them; the export has no response schema.
    /// Pass `profile` only when it is not the profile this client is scoped to.
    public func exportSession(id: String, profile: String?) async throws -> Data {
        try await sendRaw("GET", "/api/sessions/" + Self.encodedID(id) + "/export", query: Self.profileQuery(profile))
            .body
    }

    /// `GET /api/sessions/{id}` for one profile. A `404` means the server no longer has the session.
    public func session(id: String, profile: String) async throws -> SessionRecord {
        try await get("/api/sessions/" + Self.encodedID(id), query: Self.profileQuery(profile))
    }

    /// `POST /api/sessions/prune`. The answer is left raw: the contract does not describe it.
    public func pruneSessions(_ filter: SessionPruneFilter) async throws -> JSONValue {
        try await send("POST", "/api/sessions/prune", body: filter)
    }

    private static func encodedID(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private static func profileQuery(_ profile: String?) -> [URLQueryItem] {
        profile.map { [URLQueryItem(name: "profile", value: $0)] } ?? []
    }
}
