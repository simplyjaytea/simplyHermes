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

    private enum CodingKeys: String, CodingKey {
        case projects, repos, defaultCwd, home, scanEnabled
    }
}

extension WorkspaceList {
    /// Drops project rows that do not decode, so one unseen row cannot fail the whole list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([LossyRow<WorkspaceRoot>].self, forKey: .projects).compactMap { $0.value }
        repos = try container.decode([WorkspaceRoot].self, forKey: .repos)
        defaultCwd = try container.decode(String.self, forKey: .defaultCwd)
        home = try container.decodeIfPresent(String.self, forKey: .home)
        scanEnabled = try container.decode(Bool.self, forKey: .scanEnabled)
    }
}

/// Decodes one row, or nil when the row does not match its type.
private struct LossyRow<Row: Decodable>: Decodable {
    let value: Row?

    init(from decoder: Decoder) throws {
        value = try? Row(from: decoder)
    }
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
