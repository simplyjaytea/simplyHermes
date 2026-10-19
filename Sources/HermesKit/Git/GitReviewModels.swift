import Foundation

/// What the review compares. `lastTurn` needs the base ref that the chat recorded when the last turn started.
public enum GitReviewScope: String, Sendable, CaseIterable, Equatable {
    case uncommitted
    case branch
    case lastTurn
}

/// One row of `GET /api/git/review/list`. `status` is git's one-letter code: `M`, `A`, `D`, `R`, or `?` when untracked.
public struct GitReviewFile: Sendable, Equatable, Decodable, Identifiable {
    public var id: String { path }
    /// Path relative to the repository.
    public var path: String
    public var added: Int
    public var removed: Int
    public var status: String
    /// True when the change is in the index.
    public var staged: Bool
}

/// `GET /api/git/review/list`. `base` is the ref that the branch and last-turn scopes compare against.
public struct GitReviewList: Sendable, Equatable, Decodable {
    public var files: [GitReviewFile]
    public var base: String?
}

/// `GET /api/git/review/commit-context`: the diff a commit would record, and the recent commit subjects.
public struct GitCommitContext: Sendable, Equatable, Decodable {
    public var diff: String
    /// The server joins the subjects with newlines, newest first.
    public var recent: String

    /// `recent`, split into one subject per entry.
    public var recentSubjects: [String] {
        recent.split(separator: "\n").map(String.init)
    }
}

/// `GET /api/git/review/ship-info`. `ghReady` is false until `gh` is installed and signed in on the server.
public struct GitShipInfo: Sendable, Equatable, Decodable {
    public var ghReady: Bool
    /// The pull request for the current branch, when one is open.
    public var pullRequest: GitPullRequest?

    enum CodingKeys: String, CodingKey {
        case ghReady
        case pullRequest = "pr"
    }
}

/// A pull request for the current branch.
public struct GitPullRequest: Sendable, Equatable, Decodable {
    public var url: String
    public var state: String?
    public var number: Int?
}

/// `POST /api/git/review/create-pr`. The server pushes the branch first, then opens the pull request.
public struct GitCreatedPullRequest: Sendable, Equatable, Decodable {
    public var url: String
}

/// One checkout from `GET /api/git/worktrees`. The first entry is the main checkout.
public struct GitWorktree: Sendable, Equatable, Decodable, Identifiable {
    public var id: String { path }
    public var path: String
    /// The checked-out branch, or nil when the checkout is detached.
    public var branch: String?
    public var isMain: Bool
    public var detached: Bool
    public var locked: Bool
}

/// `POST /api/git/worktree/add`: the new checkout, the branch it is on, and the main repository.
public struct GitWorktreeAdded: Sendable, Equatable, Decodable {
    public var path: String
    public var branch: String
    public var repoRoot: String
}
