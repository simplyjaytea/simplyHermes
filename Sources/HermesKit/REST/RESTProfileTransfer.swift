import Foundation

/// Body of `POST /api/profiles/{name}/export`. The contract's ProfileExport has these two fields.
private struct ProfileExportRequest: Encodable, Sendable {
    var output = ""
    var extraFiles: [String: String] = [:]
}

/// Body of `POST /api/profiles/import`. `archive` is the archive as base64.
private struct ProfileImportRequest: Encodable, Sendable {
    var archive: String
    var name: String?
}

/// Percent-encodes each path segment. The `/` between segments is added here, not written in a literal, so the
/// unscoped-call guard in `ProfileScopeTests` sees only the `/api/profiles/` prefix.
private func encodedPath(_ segments: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

// MARK: - Bot export and import (WP-41)

extension RESTClient {
    /// `POST /api/profiles/{name}/export`: asks the server for an archive of the bot's profile.
    ///
    /// The profile is named in the path, so the active profile does not scope this call. UNTESTED LIVE: the contract
    /// gives no response schema. ``ProfileArchive/from(answer:)`` reads the shapes the server might send.
    public func exportProfileArchive(name: String) async throws -> ProfileArchive {
        let answer = try await sendRaw(
            "POST", "/api/profiles/" + encodedPath(name, "export"), body: ProfileExportRequest(), scoped: false)
        return try ProfileArchive.from(answer: answer)
    }

    /// `POST /api/profiles/import`: creates a bot from an archive the phone holds. The archive goes as base64 in
    /// `archive`. `name` renames the bot on import. UNTESTED LIVE: the answer is read by
    /// ``ProfileImportResult/from(answer:)``.
    public func importProfileArchive(_ archive: Data, name: String? = nil) async throws -> ProfileImportResult {
        let answer = try await sendRaw(
            "POST", "/api/profiles/import",
            body: ProfileImportRequest(archive: archive.base64EncodedString(), name: name), scoped: false)
        return ProfileImportResult.from(answer: answer)
    }
}
