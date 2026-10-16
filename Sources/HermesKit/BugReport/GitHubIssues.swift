import Foundation

/// A GitHub repository that takes bug reports.
public struct GitHubRepository: Sendable, Hashable {
    /// The owner, such as `simplyjaytea`.
    public var owner: String
    /// The repository name.
    public var name: String

    /// Creates a repository reference.
    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Where simplyHermes bug reports go.
    public static let simplyHermes = GitHubRepository(owner: "simplyjaytea", name: "simplyHermes")

    /// `https://github.com/owner/name`.
    public var webURL: URL {
        URL(string: "https://github.com/\(owner)/\(name)")!
    }

    /// A prefilled new-issue page. Works with no token: the user signs in on github.com and taps Submit.
    public func newIssueURL(for issue: GitHubIssueDraft) -> URL {
        var components = URLComponents(
            url: webURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: issue.title),
            URLQueryItem(name: "body", value: issue.body),
            URLQueryItem(name: "labels", value: issue.labels.joined(separator: ",")),
        ]
        // URLComponents leaves "+" alone, which GitHub would read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

/// An issue GitHub created.
public struct CreatedGitHubIssue: Sendable, Equatable {
    /// The issue number.
    public var number: Int
    /// The issue page.
    public var url: URL

    /// Creates a result.
    public init(number: Int, url: URL) {
        self.number = number
        self.url = url
    }
}

/// Why GitHub refused a report.
public enum GitHubIssueError: Error, Sendable, Equatable {
    /// 401: the token is wrong, expired or revoked.
    case badToken
    /// 403 or 404: the token cannot create issues in this repository.
    case noAccess
    /// 403 or 429 with no requests left.
    case rateLimited
    /// 410: issues are turned off for the repository.
    case issuesDisabled
    /// 422 or any other status. `message` is GitHub's, if it sent one.
    case rejected(status: Int, message: String?)
    /// GitHub answered 201 but the body was not an issue.
    case unexpectedResponse

    /// One sentence for the form.
    public var message: String {
        switch self {
        case .badToken: "GitHub didn't accept the token. Check it in Settings, or make a new one."
        case .noAccess:
            "The token can't create issues in simplyHermes. Give it Issues: Read and write on this repository."
        case .rateLimited: "GitHub is limiting requests right now. Try again in a few minutes."
        case .issuesDisabled: "Issues are turned off for this repository."
        case .rejected(let status, let message):
            "GitHub refused the report (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .unexpectedResponse: "GitHub sent an answer the app didn't understand."
        }
    }
}

/// Files issues with the GitHub REST API.
public struct GitHubIssueClient: Sendable {
    /// The API root, `https://api.github.com`.
    public static let apiURL = URL(string: "https://api.github.com")!

    private let transport: any HTTPTransport
    private let repository: GitHubRepository
    private let userAgent: String

    /// Creates a client. `userAgent` is required by GitHub, such as `simplyHermes/0.1.0`.
    public init(transport: any HTTPTransport, repository: GitHubRepository = .simplyHermes, userAgent: String) {
        self.transport = transport
        self.repository = repository
        self.userAgent = userAgent
    }

    /// Creates the issue. If GitHub refuses the labels (the token may not create missing ones), it tries once more
    /// without them, so the report still lands.
    public func create(_ issue: GitHubIssueDraft, token: String) async throws -> CreatedGitHubIssue {
        do {
            return try await send(issue, token: token)
        } catch GitHubIssueError.rejected(status: 422, _) where !issue.labels.isEmpty {
            var unlabeled = issue
            unlabeled.labels = []
            return try await send(unlabeled, token: token)
        }
    }

    private func send(_ issue: GitHubIssueDraft, token: String) async throws -> CreatedGitHubIssue {
        let url = Self.apiURL.appendingPathComponent("repos/\(repository.owner)/\(repository.name)/issues")
        var payload: [String: JSONValue] = ["title": .string(issue.title), "body": .string(issue.body)]
        if !issue.labels.isEmpty { payload["labels"] = .array(issue.labels.map(JSONValue.string)) }
        let request = HTTPRequest(
            method: "POST", url: url,
            headers: [
                "Accept": "application/vnd.github+json",
                "Authorization": "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
                "Content-Type": "application/json",
                "User-Agent": userAgent,
                "X-GitHub-Api-Version": "2022-11-28",
            ],
            body: try JSONEncoder().encode(payload))
        let response = try await transport.send(request)
        guard response.status == 201 else { throw Self.error(for: response) }
        guard let created = try? JSONDecoder().decode(CreatedBody.self, from: response.body),
            let page = URL(string: created.htmlURL)
        else { throw GitHubIssueError.unexpectedResponse }
        return CreatedGitHubIssue(number: created.number, url: page)
    }

    static func error(for response: HTTPResponse) -> GitHubIssueError {
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: response.body))?.message
        switch response.status {
        case 401: return .badToken
        case 403 where response.headers["x-ratelimit-remaining"] == "0", 429: return .rateLimited
        case 403 where message?.localizedCaseInsensitiveContains("rate limit") == true: return .rateLimited
        case 403, 404: return .noAccess
        case 410: return .issuesDisabled
        default: return .rejected(status: response.status, message: message)
        }
    }
}

private struct CreatedBody: Decodable {
    let number: Int
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

private struct ErrorBody: Decodable {
    let message: String?
}
