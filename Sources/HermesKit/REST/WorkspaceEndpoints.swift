import Foundation

// MARK: - Workspaces and files

extension RESTClient {
    /// `GET /api/chat/workspaces`.
    public func workspaces() async throws -> WorkspaceList { try await get("/api/chat/workspaces") }

    /// `GET /api/fs/list`: the entries of one folder on the server.
    public func listFolder(_ path: String) async throws -> FsList {
        try await get("/api/fs/list", query: [URLQueryItem(name: "path", value: path)])
    }

    /// `GET /api/fs/read-text`: one file on the server, with its type. Binary files carry no `text`.
    public func readText(_ path: String) async throws -> FsText {
        try await get("/api/fs/read-text", query: [URLQueryItem(name: "path", value: path)])
    }
}
