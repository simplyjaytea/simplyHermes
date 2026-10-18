import Foundation

/// `GET /api/hermes/update/check`. The field list is the endpoint's own description, so every field is read
/// leniently: a field of an unexpected type is nil.
public struct HermesUpdateCheck: Sendable, Equatable, Decodable {
    /// `apt`, `git`, `docker`, `nix`, `nixos` or `unknown`.
    public var installMethod: String?
    /// The installed version.
    public var currentVersion: String?
    /// Commits behind: 0 is up to date, -1 an unknown count, nil a check that could not run.
    public var behind: Int?
    /// True when an update exists.
    public var updateAvailable: Bool?
    /// True when the dashboard can apply the update in place (git installs only).
    public var canApply: Bool?
    /// The command to run by hand when the dashboard cannot apply it.
    public var updateCommand: String?
    /// Guidance for installs the dashboard cannot update.
    public var message: String?
    /// The commits the install is behind, for git installs.
    public var commits: [HermesUpdateCommit]?

    private enum CodingKeys: String, CodingKey {
        case installMethod, currentVersion, behind, updateAvailable, canApply, updateCommand, message, commits
    }

    /// Reads each field on its own.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        installMethod = try? values.decodeIfPresent(String.self, forKey: .installMethod)
        currentVersion = try? values.decodeIfPresent(String.self, forKey: .currentVersion)
        behind = try? values.decodeIfPresent(Int.self, forKey: .behind)
        updateAvailable = try? values.decodeIfPresent(Bool.self, forKey: .updateAvailable)
        canApply = try? values.decodeIfPresent(Bool.self, forKey: .canApply)
        updateCommand = try? values.decodeIfPresent(String.self, forKey: .updateCommand)
        message = try? values.decodeIfPresent(String.self, forKey: .message)
        commits = try? values.decodeIfPresent([HermesUpdateCommit].self, forKey: .commits)
    }

    /// Creates a value from its fields, for previews and tests.
    public init(
        installMethod: String? = nil, currentVersion: String? = nil, behind: Int? = nil,
        updateAvailable: Bool? = nil, canApply: Bool? = nil, updateCommand: String? = nil, message: String? = nil,
        commits: [HermesUpdateCommit]? = nil
    ) {
        self.installMethod = installMethod
        self.currentVersion = currentVersion
        self.behind = behind
        self.updateAvailable = updateAvailable
        self.canApply = canApply
        self.updateCommand = updateCommand
        self.message = message
        self.commits = commits
    }
}

/// One commit in ``HermesUpdateCheck/commits``: `{sha, summary, author, at}`.
public struct HermesUpdateCommit: Sendable, Equatable, Decodable {
    /// The commit id.
    public var sha: String?
    /// The first line of the commit message.
    public var summary: String?
    /// The author.
    public var author: String?
    /// When the commit was made, as the server writes it.
    public var at: String?

    private enum CodingKeys: String, CodingKey {
        case sha, summary, author, at
    }

    /// Reads each field on its own.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sha = try? values.decodeIfPresent(String.self, forKey: .sha)
        summary = try? values.decodeIfPresent(String.self, forKey: .summary)
        author = try? values.decodeIfPresent(String.self, forKey: .author)
        at = try? values.decodeIfPresent(String.self, forKey: .at)
    }

    /// Creates a commit, for previews and tests.
    public init(sha: String? = nil, summary: String? = nil, author: String? = nil, at: String? = nil) {
        self.sha = sha
        self.summary = summary
        self.author = author
        self.at = at
    }
}
