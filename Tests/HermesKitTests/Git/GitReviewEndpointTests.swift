import Foundation
import HermesKit
import Testing

/// Each test serves a response in the shape `web_git.py` returns, and checks the request the facade built.
@Suite struct GitReviewEndpointTests {
    private func client(_ http: FakeHTTP) throws -> RESTClient {
        RESTClient(endpoint: try #require(HermesEndpoint(string: "http://h:1")), transport: http)
    }

    /// The JSON object a request carried.
    private func body(_ request: HTTPRequest?) throws -> [String: Any] {
        let data = try #require(request?.body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func reviewListDecodesFilesAndSendsTheScope() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200, #"{"files":[{"path":"App.swift","added":2,"removed":1,"status":"M","staged":true}],"base":null}"#)
        let list = try await client(http).gitReviewList(path: "/srv/hermes", scope: .uncommitted)
        let request = try #require(http.requests.first)
        #expect(list.files.first?.path == "App.swift" && list.files.first?.staged == true)
        #expect(list.base == nil)
        #expect(request.url.path == "/api/git/review/list")
        #expect(request.url.query?.contains("scope=uncommitted") == true)
    }

    @Test func diffReturnsTheTextAndSendsTheStagedFlag() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"diff":"@@ -1 +1 @@\n-a\n+b\n"}"#)
        let diff = try await client(http).gitReviewDiff(
            path: "/srv/hermes", file: "App.swift", scope: .uncommitted, staged: true)
        let request = try #require(http.requests.first)
        #expect(diff == "@@ -1 +1 @@\n-a\n+b\n")
        #expect(request.url.query?.contains("staged=true") == true)
        #expect(request.url.query?.contains("file=App.swift") == true)
    }

    @Test func commitContextSplitsTheRecentSubjects() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"diff":"","recent":"Add terminal\nFix pty"}"#)
        let context = try await client(http).gitCommitContext(path: "/srv/hermes")
        #expect(context.recentSubjects == ["Add terminal", "Fix pty"])
    }

    @Test func shipInfoReadsAnOpenPullRequest() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ghReady":true,"pr":{"url":"https://github.com/o/r/pull/9","state":"OPEN","number":9}}"#)
        let info = try await client(http).gitShipInfo(path: "/srv/hermes")
        #expect(info.ghReady && info.pullRequest?.number == 9 && info.pullRequest?.state == "OPEN")
    }

    @Test func shipInfoWithoutAPullRequestHasNoPR() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ghReady":false,"pr":null}"#)
        let info = try await client(http).gitShipInfo(path: "/srv/hermes")
        #expect(!info.ghReady && info.pullRequest == nil)
    }

    @Test func createPullRequestReturnsTheURL() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"url":"https://github.com/o/r/pull/10"}"#)
        let created = try await client(http).gitCreatePullRequest(path: "/srv/hermes")
        #expect(created.url.hasSuffix("/pull/10"))
        #expect(http.requests.first?.method == "POST")
    }

    @Test func commitPostsPropertyNamesAsKeys() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        try await client(http).gitCommit(path: "/srv/hermes", message: "Add terminal", push: true)
        let request = try #require(http.requests.first)
        let sent = try body(request)
        #expect(request.method == "POST" && request.url.path == "/api/git/review/commit")
        #expect(sent["path"] as? String == "/srv/hermes")
        #expect(sent["message"] as? String == "Add terminal" && sent["push"] as? Bool == true)
    }

    @Test func stageAllOmitsTheFileKey() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        try await client(http).gitStage(path: "/srv/hermes", file: nil)
        let sent = try body(http.requests.first)
        #expect(sent["file"] == nil)
        #expect(sent["path"] as? String == "/srv/hermes")
    }

    @Test func worktreeRemoveKeepsTheCamelCaseKey() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"removed":"/srv/wt"}"#)
        try await client(http).gitWorktreeRemove(path: "/srv/hermes", worktreePath: "/srv/wt", force: true)
        let sent = try body(http.requests.first)
        #expect(sent["worktreePath"] as? String == "/srv/wt" && sent["force"] as? Bool == true)
        #expect(sent["worktree_path"] == nil)
    }

    @Test func worktreesDecodeTheMainCheckoutFirst() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"worktrees":[{"path":"/srv/hermes","branch":"main","isMain":true,"detached":false,"locked":false},"#
                + #"{"path":"/srv/wt","branch":null,"isMain":false,"detached":true,"locked":false}]}"#)
        let trees = try await client(http).gitWorktrees(path: "/srv/hermes")
        #expect(trees.map(\.isMain) == [true, false])
        #expect(trees[1].branch == nil && trees[1].detached)
        #expect(http.requests.first?.url.query?.contains("path=") == true)
    }

    @Test func worktreeAddDecodesTheNewCheckout() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"path":"/srv/wt","branch":"hermes/wt","repoRoot":"/srv/hermes"}"#)
        let added = try await client(http).gitWorktreeAdd(path: "/srv/hermes", name: "wt", branch: nil, base: nil)
        #expect(added.branch == "hermes/wt" && added.repoRoot == "/srv/hermes")
    }

    @Test func failedMutationKeepsGitsMessage() async throws {
        let http = FakeHTTP()
        http.enqueue(400, #"{"detail":"error: pathspec 'x' did not match any files"}"#)
        do {
            try await client(http).gitStage(path: "/srv/hermes", file: "x")
            Issue.record("a 400 answer should throw")
        } catch {
            let restError = try #require(error as? RESTError)
            #expect(restError == RESTError.http(status: 400, detail: "error: pathspec 'x' did not match any files"))
        }
    }
}
