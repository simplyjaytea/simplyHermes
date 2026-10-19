#if canImport(SwiftUI)
    import HermesKit
    import SwiftUI

    extension GitReviewScope {
        /// The scopes the picker offers. Last turn waits until the chat records where each turn started.
        static let reviewable: [GitReviewScope] = [.uncommitted, .branch]

        var title: String {
            switch self {
            case .uncommitted: "Uncommitted"
            case .branch: "Branch"
            case .lastTurn: "Last turn"
            }
        }
    }

    /// The git review for one repository: a scope picker, the staged and unstaged files, and the commands that change
    /// them. Tapping a file opens its diff.
    struct GitReviewScreen: View {
        @State private var model: GitReviewModel
        @State private var showingCommit = false
        @State private var showingWorktrees = false
        @State private var confirmingPullRequest = false
        @State private var confirmingRevert = false
        @State private var revertTarget: GitReviewFile?

        init(repoPath: String, connections: ConnectionsModel?) {
            _model = State(initialValue: GitReviewModel(repoPath: repoPath, connections: connections))
        }

        var body: some View {
            List {
                Section {
                    Picker("Scope", selection: Bindable(model).scope) {
                        ForEach(GitReviewScope.reviewable, id: \.self) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                fileSection("Staged", files: model.staged)
                fileSection("Unstaged", files: model.unstaged)
                shipSection
                if let errorText = model.errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .overlay {
                if !model.loading && model.files.isEmpty && model.errorText == nil {
                    ContentUnavailableView(
                        "No changes", systemImage: "checkmark.circle",
                        description: Text("This scope has no changed files."))
                }
            }
            .navigationTitle("Git review")
            .toolbar { toolbar }
            .task(id: model.scope) { await model.reload() }
            .refreshable { await model.reload() }
            .sheet(isPresented: $showingCommit) {
                GitCommitSheet(model: model)
            }
            .sheet(isPresented: $showingWorktrees) {
                NavigationStack {
                    GitWorktreesScreen(model: model)
                }
            }
            .confirmationDialog("Create a pull request?", isPresented: $confirmingPullRequest) {
                Button("Push and open pull request") {
                    Task { await model.createPullRequest() }
                }
            } message: {
                Text("The server pushes this branch, then runs gh pr create --fill.")
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingRevert) {
                Button("Discard changes", role: .destructive) {
                    if let file = revertTarget {
                        Task { await model.revert(file) }
                    }
                }
            } message: {
                Text(revertTarget.map { "\($0.path) returns to HEAD. Untracked files are deleted." } ?? "")
            }
        }

        @ViewBuilder
        private func fileSection(_ title: LocalizedStringKey, files: [GitReviewFile]) -> some View {
            if !files.isEmpty {
                Section(title) {
                    ForEach(files) { file in
                        NavigationLink {
                            GitDiffScreen(model: model, file: file)
                        } label: {
                            GitReviewFileRow(file: file)
                        }
                        .swipeActions(edge: .trailing) {
                            swipeActions(for: file)
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func swipeActions(for file: GitReviewFile) -> some View {
            if file.staged {
                Button("Unstage") { Task { await model.unstage(file) } }
                    .tint(.orange)
            } else {
                Button("Stage") { Task { await model.stage(file) } }
                    .tint(.green)
            }
            Button("Revert", role: .destructive) {
                revertTarget = file
                confirmingRevert = true
            }
        }

        @ViewBuilder
        private var shipSection: some View {
            let link = model.pullRequestURL ?? model.ship?.pullRequest?.url
            if model.ship?.ghReady == false {
                Section {
                    Text("Install and sign in to gh on the server to open pull requests.")
                        .font(.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            if let link, let url = URL(string: link) {
                Section {
                    Link("Open pull request", destination: url)
                }
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .primaryAction) {
                Button("Commit", systemImage: "checkmark.circle") { showingCommit = true }
                    .disabled(model.files.isEmpty || model.working)
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Create pull request", systemImage: "arrow.triangle.pull") {
                        confirmingPullRequest = true
                    }
                    .disabled(model.ship?.ghReady != true || model.working)
                    Button("Worktrees", systemImage: "rectangle.stack") { showingWorktrees = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    /// One changed file: its status letter, its path, and the line counts.
    private struct GitReviewFileRow: View {
        let file: GitReviewFile

        var body: some View {
            HStack(spacing: 12) {
                Text(file.status)
                    .font(HermesFont.code.weight(.semibold))
                    .foregroundStyle(HermesColor.secondaryText)
                    .frame(width: 22)
                Text(file.path)
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("+\(file.added) \u{2212}\(file.removed)")
                    .font(HermesFont.code)
                    .foregroundStyle(HermesColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
