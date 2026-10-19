#if canImport(SwiftUI)
    import HermesKit
    import Observation

    /// Thrown when no server is connected, so the review cannot reach the repository.
    enum GitReviewError: Error {
        case noServer
    }

    /// One repository's review on the active server: the scope, the changed files, the worktrees, and the actions that
    /// change them. A change that succeeds reloads the list. Errors go to `errorText` for the screen to show.
    @MainActor
    @Observable
    final class GitReviewModel {
        let repoPath: String
        var scope: GitReviewScope = .uncommitted
        private(set) var files: [GitReviewFile] = []
        private(set) var worktrees: [GitWorktree] = []
        private(set) var ship: GitShipInfo?
        /// The pull request that the last `createPullRequest` opened.
        private(set) var pullRequestURL: String?
        private(set) var loading = false
        private(set) var working = false
        private(set) var errorText: String?

        private let connections: ConnectionsModel?

        init(repoPath: String, connections: ConnectionsModel?) {
            self.repoPath = repoPath
            self.connections = connections
        }

        var staged: [GitReviewFile] { files.filter(\.staged) }
        var unstaged: [GitReviewFile] { files.filter { !$0.staged } }

        /// Reloads the changed files for the current scope, the ship state, and the worktrees.
        func reload() async {
            loading = true
            defer { loading = false }
            do {
                let rest = try await restClient()
                files = try await rest.gitReviewList(path: repoPath, scope: scope).files
                ship = try? await rest.gitShipInfo(path: repoPath)
                worktrees = (try? await rest.gitWorktrees(path: repoPath)) ?? []
                errorText = nil
            } catch {
                errorText = Self.describe(error)
            }
        }

        func stage(_ file: GitReviewFile) async {
            let path = repoPath
            _ = await change { try await $0.gitStage(path: path, file: file.path) }
        }

        func unstage(_ file: GitReviewFile) async {
            let path = repoPath
            _ = await change { try await $0.gitUnstage(path: path, file: file.path) }
        }

        /// Restores a file to HEAD. Untracked files are deleted, so the view confirms first.
        func revert(_ file: GitReviewFile) async {
            let path = repoPath
            _ = await change { try await $0.gitRevert(path: path, file: file.path) }
        }

        /// Commits what is staged, or everything when nothing is staged. Returns false when the server refused.
        func commit(message: String, push: Bool) async -> Bool {
            let path = repoPath
            return await change { try await $0.gitCommit(path: path, message: message, push: push) }
        }

        /// Pushes the current branch and opens a pull request for it. The view confirms first.
        func createPullRequest() async {
            let path = repoPath
            working = true
            defer { working = false }
            do {
                let rest = try await restClient()
                pullRequestURL = try await rest.gitCreatePullRequest(path: path).url
                ship = try? await rest.gitShipInfo(path: path)
                errorText = nil
            } catch {
                errorText = Self.describe(error)
            }
        }

        /// Adds a linked worktree. Returns false when the server refused.
        func addWorktree(name: String?, branch: String?, base: String?) async -> Bool {
            let path = repoPath
            return await change {
                _ = try await $0.gitWorktreeAdd(path: path, name: name, branch: branch, base: base)
            }
        }

        /// Removes a linked worktree. `force` also removes one with uncommitted changes.
        func removeWorktree(_ worktree: GitWorktree, force: Bool) async {
            let path = repoPath
            let target = worktree.path
            _ = await change { try await $0.gitWorktreeRemove(path: path, worktreePath: target, force: force) }
        }

        func commitContext() async -> GitCommitContext? {
            let path = repoPath
            do {
                return try await restClient().gitCommitContext(path: path)
            } catch {
                errorText = Self.describe(error)
                return nil
            }
        }

        /// The unified diff of one file in the current scope, or nil when the server refused.
        func diff(for file: GitReviewFile) async -> String? {
            let path = repoPath
            let scope = self.scope
            do {
                return try await restClient().gitReviewDiff(
                    path: path, file: file.path, scope: scope, staged: file.staged)
            } catch {
                errorText = Self.describe(error)
                return nil
            }
        }

        /// Runs one change on the server, then reloads. Returns false, with `errorText` set, when the server refuses it.
        private func change(_ work: (RESTClient) async throws -> Void) async -> Bool {
            working = true
            defer { working = false }
            do {
                let rest = try await restClient()
                try await work(rest)
            } catch {
                errorText = Self.describe(error)
                return false
            }
            await reload()
            return true
        }

        /// The REST client of the active server, connecting first when needed.
        private func restClient() async throws -> RESTClient {
            guard let connections, let manager = connections.manager, let active = connections.active else {
                throw GitReviewError.noServer
            }
            _ = try await manager.client(for: active)
            guard let rest = await manager.rest(for: active.id) else {
                throw GitReviewError.noServer
            }
            return rest
        }

        /// The server's own message when it refused a request, otherwise a short general line.
        private static func describe(_ error: any Error) -> String {
            if let restError = error as? RESTError, case .http(_, let detail?) = restError {
                return detail
            }
            if error is GitReviewError {
                return "Connect a server first."
            }
            return "The server did not finish the git request."
        }
    }
#endif
