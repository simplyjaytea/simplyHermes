import Foundation

// The git routes take camelCase keys, and the REST encoder would rename them to snake_case. These bodies go out
// through `sendRaw(json:)` with a plain encoder, so each property name is the wire key.

private struct GitPathBody: Encodable, Sendable {
    let path: String
}

private struct GitFileBody: Encodable, Sendable {
    let path: String
    /// Nil acts on every changed file.
    let file: String?
}

private struct GitCommitBody: Encodable, Sendable {
    let path: String
    let message: String
    let push: Bool
}

private struct GitWorktreeAddBody: Encodable, Sendable {
    let path: String
    let name: String?
    let branch: String?
    let base: String?
}

private struct GitWorktreeRemoveBody: Encodable, Sendable {
    let path: String
    let worktreePath: String
    let force: Bool
}

private struct GitDiffText: Decodable, Sendable {
    let diff: String
}

private struct GitWorktreeList: Decodable, Sendable {
    let worktrees: [GitWorktree]
}

private struct GitAck: Decodable, Sendable {}

private func gitQuery(_ pairs: KeyValuePairs<String, String?>) -> [URLQueryItem] {
    pairs.compactMap { pair in pair.value.map { URLQueryItem(name: pair.key, value: $0) } }
}

// MARK: - Git review (WP-62)

extension RESTClient {
    /// `GET /api/git/review/list`: the changed files in `scope`.
    public func gitReviewList(path: String, scope: GitReviewScope, base: String? = nil) async throws -> GitReviewList {
        try await get("/api/git/review/list", query: gitQuery(["path": path, "scope": scope.rawValue, "base": base]))
    }

    /// `GET /api/git/review/diff`: the unified diff of one file. `staged` selects the index side.
    public func gitReviewDiff(
        path: String, file: String, scope: GitReviewScope, base: String? = nil, staged: Bool = false
    ) async throws -> String {
        let answer: GitDiffText = try await get(
            "/api/git/review/diff",
            query: gitQuery([
                "path": path, "file": file, "scope": scope.rawValue, "base": base,
                "staged": staged ? "true" : nil,
            ]))
        return answer.diff
    }

    /// `GET /api/git/review/commit-context`: the diff a commit would record, and the recent commit subjects.
    public func gitCommitContext(path: String) async throws -> GitCommitContext {
        try await get("/api/git/review/commit-context", query: gitQuery(["path": path]))
    }

    /// `POST /api/git/review/stage`. A nil `file` stages every change.
    public func gitStage(path: String, file: String?) async throws {
        _ = try await gitPost("/api/git/review/stage", GitFileBody(path: path, file: file), as: GitAck.self)
    }

    /// `POST /api/git/review/unstage`. A nil `file` unstages every change.
    public func gitUnstage(path: String, file: String?) async throws {
        _ = try await gitPost("/api/git/review/unstage", GitFileBody(path: path, file: file), as: GitAck.self)
    }

    /// `POST /api/git/review/revert`. Restores tracked files and deletes untracked ones. A nil `file` covers all.
    public func gitRevert(path: String, file: String?) async throws {
        _ = try await gitPost("/api/git/review/revert", GitFileBody(path: path, file: file), as: GitAck.self)
    }

    /// `POST /api/git/review/commit`. Stages everything when nothing is staged. `push` pushes after the commit.
    public func gitCommit(path: String, message: String, push: Bool) async throws {
        _ = try await gitPost(
            "/api/git/review/commit", GitCommitBody(path: path, message: message, push: push), as: GitAck.self)
    }

    /// `GET /api/git/review/ship-info`: whether `gh` is ready, and the open pull request for this branch.
    public func gitShipInfo(path: String) async throws -> GitShipInfo {
        try await get("/api/git/review/ship-info", query: gitQuery(["path": path]))
    }

    /// `POST /api/git/review/create-pr`. The server pushes the branch, then runs `gh pr create --fill`.
    public func gitCreatePullRequest(path: String) async throws -> GitCreatedPullRequest {
        try await gitPost("/api/git/review/create-pr", GitPathBody(path: path), as: GitCreatedPullRequest.self)
    }

    /// `GET /api/git/worktrees`: the main checkout and each linked worktree.
    public func gitWorktrees(path: String) async throws -> [GitWorktree] {
        let list: GitWorktreeList = try await get("/api/git/worktrees", query: gitQuery(["path": path]))
        return list.worktrees
    }

    /// `POST /api/git/worktree/add`. Without `branch`, the server names a `hermes/` branch after `name`.
    public func gitWorktreeAdd(
        path: String, name: String?, branch: String?, base: String?
    ) async throws -> GitWorktreeAdded {
        try await gitPost(
            "/api/git/worktree/add", GitWorktreeAddBody(path: path, name: name, branch: branch, base: base),
            as: GitWorktreeAdded.self)
    }

    /// `POST /api/git/worktree/remove`. `force` also removes a checkout that has uncommitted changes.
    public func gitWorktreeRemove(path: String, worktreePath: String, force: Bool) async throws {
        _ = try await gitPost(
            "/api/git/worktree/remove", GitWorktreeRemoveBody(path: path, worktreePath: worktreePath, force: force),
            as: GitAck.self)
    }

    /// Posts `body` as JSON, with its property names as the keys, and decodes the answer.
    private func gitPost<Body: Encodable & Sendable, Answer: Decodable & Sendable>(
        _ path: String, _ body: Body, as answer: Answer.Type
    ) async throws -> Answer {
        let json = try JSONEncoder().encode(body)
        let response = try await sendRaw("POST", path, json: json)
        do {
            return try RESTClient.decoder.decode(Answer.self, from: response.body)
        } catch {
            throw RESTError.decoding("\(error)")
        }
    }
}
