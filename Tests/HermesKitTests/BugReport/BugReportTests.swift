import Foundation
import Testing

@testable import HermesKit

@Suite struct DiagnosticsRedactorTests {
    private let redactor = DiagnosticsRedactor(knownValues: ["Home server", "jt", "nas"])

    @Test func tokensAndKeysAreRemoved() {
        let text = """
            Authorization: Bearer abcdef123456
            got ghp_ABCDEFGHIJKLMNOPQRSTuvwx and github_pat_11ABCDEFG0123456789_abcdefghij
            jwt eyJhbGciOi.eyJzdWIiOi.SflKxwRJSM
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAA
            -----END OPENSSH PRIVATE KEY-----
            """
        let out = redactor.redact(text)
        #expect(!out.contains("abcdef123456"))
        #expect(!out.contains("ghp_"))
        #expect(!out.contains("github_pat_"))
        #expect(!out.contains("eyJ"))
        #expect(!out.contains("b3BlbnNz"))
        #expect(out.contains("[redacted key]"))
    }

    @Test func keyValueSecretsKeepTheKey() {
        let out = redactor.redact(#"password=hunter22 {"refresh_token": "r-123"} cookie: hermes_session=xyz"#)
        #expect(out.contains("password=[redacted]"))
        #expect(out.contains(#""refresh_token": "[redacted]"#))
        #expect(!out.contains("hunter22") && !out.contains("r-123") && !out.contains("xyz"))
    }

    @Test func addressesAreRemovedButPortsAndPathsStay() {
        let out = redactor.redact(
            "GET https://user:pw@hermes.example.com:9119/api/status from 192.168.1.20, fd00:1:2:3::9 and box.tail1.ts.net"
        )
        #expect(out.contains("https://[host]:9119/api/status"))
        #expect(!out.contains("example.com") && !out.contains("pw@"))
        #expect(out.contains("[ip]") && !out.contains("192.168"))
        #expect(!out.contains("tail1"))
    }

    @Test func emailsAndKnownValuesAreRemoved() {
        let out = redactor.redact("signed in as me@example.org on Home server via NAS")
        #expect(!out.contains("me@example.org") && out.contains("[redacted email]"))
        #expect(!out.contains("Home server") && !out.lowercased().contains("nas"))
    }

    @Test func shortKnownValuesAndTimesAreLeftAlone() {
        let out = redactor.redact("12:30:45.123 just a line about jt")
        #expect(out.hasPrefix("12:30:45.123 just a line"))
    }
}

@Suite struct BugReportComposerTests {
    private let diagnostics = BugReportDiagnostics(
        appVersion: "0.1.0", build: "7", system: "iOS 27.1", device: "iPhone19,1", layout: "innerLandscape",
        posture: "flat", connectionKind: "gateway", connectionState: "connected", serverVersion: "git.d97007c",
        logLines: ["[Gateway] connect to https://home.example.com:9119 token=abc", "[UI] tap"])

    @Test func bodyHasTheUsersTextAndRedactedDiagnostics() {
        let draft = BugReportDraft(
            title: "  Chat freezes  ", whatHappened: "It froze.", steps: "1. Open chat", expected: "")
        let issue = BugReportComposer.issue(draft: draft, diagnostics: diagnostics, redactor: DiagnosticsRedactor())
        #expect(issue.title == "Chat freezes")
        #expect(issue.labels == ["bug", "in-app report"])
        #expect(issue.body.contains("### What happened\n\nIt froze."))
        #expect(issue.body.contains("### Steps to reproduce\n\n1. Open chat"))
        #expect(!issue.body.contains("### Expected"))
        #expect(issue.body.contains("| App | 0.1.0 (7) |"))
        #expect(issue.body.contains("| Layout | innerLandscape |"))
        #expect(issue.body.contains("Recent log (2 lines)"))
        #expect(!issue.body.contains("home.example.com") && !issue.body.contains("token=abc"))
    }

    @Test func diagnosticsCanBeLeftOut() {
        let draft = BugReportDraft(title: "t", whatHappened: "w", includesDiagnostics: false)
        let issue = BugReportComposer.issue(draft: draft, diagnostics: diagnostics, redactor: DiagnosticsRedactor())
        #expect(!issue.body.contains("Diagnostics"))
    }

    @Test func logKeepsTheNewestLinesWithinBudget() {
        let lines = (1...100).map { "line \($0)" }
        let kept = BugReportComposer.recentLog(lines, budget: 40)
        #expect(kept.last == "line 100")
        #expect(kept.joined(separator: "\n").count <= 40)
        #expect(kept == kept.sorted { Int($0.dropFirst(5))! < Int($1.dropFirst(5))! })
    }

    @Test func draftNeedsTitleAndDescription() {
        #expect(!BugReportDraft(title: "x").isComplete)
        #expect(!BugReportDraft(title: " ", whatHappened: "y").isComplete)
        #expect(BugReportDraft(title: "x", whatHappened: "y").isComplete)
    }
}

@Suite struct GitHubIssueClientTests {
    private let issue = GitHubIssueDraft(title: "Crash", body: "Body", labels: ["bug"])

    @Test func createsTheIssueWithTheRightRequest() async throws {
        let http = FakeHTTP()
        http.enqueue(201, #"{"number":42,"html_url":"https://github.com/simplyjaytea/simplyHermes/issues/42"}"#)
        let client = GitHubIssueClient(transport: http, userAgent: "simplyHermes/0.1.0")
        let created = try await client.create(issue, token: " github_pat_x \n")
        #expect(created.number == 42)
        #expect(created.url.absoluteString.hasSuffix("/issues/42"))
        let request = try #require(http.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.github.com/repos/simplyjaytea/simplyHermes/issues")
        #expect(request.headers["Authorization"] == "Bearer github_pat_x")
        #expect(request.headers["X-GitHub-Api-Version"] == "2022-11-28")
        let sent = try JSONDecoder().decode([String: JSONValue].self, from: try #require(request.body))
        #expect(sent["labels"] == .array([.string("bug")]))
    }

    @Test func retriesWithoutLabelsWhenGitHubRefusesThem() async throws {
        let http = FakeHTTP()
        http.enqueue(422, #"{"message":"Validation Failed"}"#)
        http.enqueue(201, #"{"number":7,"html_url":"https://github.com/simplyjaytea/simplyHermes/issues/7"}"#)
        let client = GitHubIssueClient(transport: http, userAgent: "t")
        let created = try await client.create(issue, token: "t")
        #expect(created.number == 7)
        let retry = try JSONDecoder().decode([String: JSONValue].self, from: try #require(http.requests[1].body))
        #expect(retry["labels"] == nil)
    }

    @Test func mapsStatusesToErrors() {
        func error(_ status: Int, _ body: String = "{}", _ headers: [String: String] = [:]) -> GitHubIssueError {
            GitHubIssueClient.error(for: HTTPResponse(status: status, headers: headers, body: Data(body.utf8)))
        }
        #expect(error(401) == .badToken)
        #expect(error(404) == .noAccess)
        #expect(error(403) == .noAccess)
        #expect(error(403, "{}", ["X-RateLimit-Remaining": "0"]) == .rateLimited)
        #expect(error(403, #"{"message":"API rate limit exceeded"}"#) == .rateLimited)
        #expect(error(410) == .issuesDisabled)
        #expect(error(500, #"{"message":"boom"}"#) == .rejected(status: 500, message: "boom"))
    }

    @Test func newIssueURLIsPrefilled() throws {
        let url = GitHubRepository.simplyHermes.newIssueURL(
            for: GitHubIssueDraft(title: "A + B", body: "x&y", labels: ["bug", "in-app report"]))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/simplyjaytea/simplyHermes/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["title"] == "A + B")
        #expect(items["body"] == "x&y")
        #expect(items["labels"] == "bug,in-app report")
        #expect(url.absoluteString.contains("A%20%2B%20B"))
    }
}

@Suite struct GitHubTokenTests {
    @Test func pastedTokensAreTrimmed() {
        #expect(GitHubToken.cleaned("  github_pat_abc\n") == "github_pat_abc")
        #expect(GitHubToken.cleaned(" \n ") == nil)
    }

    @Test func storeReportsWhetherATokenIsSaved() throws {
        let store = InMemoryGitHubTokenStore()
        #expect(!store.hasToken)
        try store.setToken("t")
        #expect(store.hasToken)
        try store.removeToken()
        #expect(!store.hasToken)
    }

    @Test func createURLAsksForIssuesWrite() throws {
        let components = try #require(URLComponents(url: GitHubToken.createURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/settings/personal-access-tokens/new")
        #expect(components.queryItems?.contains(URLQueryItem(name: "issues", value: "write")) == true)
    }
}
