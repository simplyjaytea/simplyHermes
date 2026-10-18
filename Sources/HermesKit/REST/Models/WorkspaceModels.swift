import Foundation

/// A folder the server offers as a workspace: a git repo or a project it found.
public struct WorkspaceRoot: Decodable, Sendable, Equatable, Identifiable {
    /// Absolute path on the server.
    public var root: String
    /// Short name for the picker.
    public var label: String?
    /// Chats that run in this folder.
    public var sessions: Int?
    /// Last activity, in seconds since 1970.
    public var lastActive: Double?

    public var id: String { root }
}

/// `GET /api/chat/workspaces`: the folders a chat can run in, and the one a new chat starts in.
public struct WorkspaceList: Decodable, Sendable, Equatable {
    public var projects: [WorkspaceRoot]
    public var repos: [WorkspaceRoot]
    /// The folder a new chat starts in.
    public var defaultCwd: String
    /// The server user's home folder.
    public var home: String?
    /// Whether the server scans for more workspaces.
    public var scanEnabled: Bool
}

/// One item of a folder listing.
public struct FsEntry: Decodable, Sendable, Equatable, Identifiable {
    public var name: String
    /// Absolute path on the server.
    public var path: String
    public var isDirectory: Bool

    public var id: String { path }
}

/// `GET /api/fs/list`. A missing or unreadable folder answers 200 with `error` set and no entries.
public struct FsList: Decodable, Sendable, Equatable {
    public var entries: [FsEntry]
    /// Such as `ENOENT`.
    public var error: String?
}

/// `GET /api/fs/read-text`. `text` is nil for binary files.
public struct FsText: Decodable, Sendable, Equatable {
    public var path: String
    public var text: String?
    public var binary: Bool
    public var byteSize: Int?
    public var mimeType: String?
    public var language: String?
}
