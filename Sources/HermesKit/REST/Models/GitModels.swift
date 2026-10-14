import Foundation

/// One changed file in `GET /api/git/status`.
public struct GitChangedFile: Sendable, Equatable, Codable {
    /// Path relative to the repository.
    public var path: String
    /// Has staged changes.
    public var staged: Bool?
    /// Has unstaged changes.
    public var unstaged: Bool?
    /// Not tracked yet.
    public var untracked: Bool?
    /// Has merge conflicts.
    public var conflicted: Bool?
}

/// `GET /api/git/status?path=`.
public struct GitStatus: Sendable, Equatable, Codable {
    /// Current branch. Nil when detached or not a repository.
    public var branch: String?
    /// Default branch of the remote.
    public var defaultBranch: String?
    /// True on a detached HEAD.
    public var detached: Bool?
    /// Commits ahead of upstream.
    public var ahead: Int?
    /// Commits behind upstream.
    public var behind: Int?
    /// Files with staged changes.
    public var staged: Int?
    /// Files with unstaged changes.
    public var unstaged: Int?
    /// Untracked files.
    public var untracked: Int?
    /// Files with conflicts.
    public var conflicted: Int?
    /// Added lines.
    public var added: Int?
    /// Removed lines.
    public var removed: Int?
    /// Changed files.
    public var files: [GitChangedFile]?
}
