#if canImport(SwiftUI)
    import HermesKit
    import SwiftUI

    /// The repository's checkouts. Linked worktrees can be added and removed. The main checkout stays.
    struct GitWorktreesScreen: View {
        let model: GitReviewModel

        @Environment(\.dismiss) private var dismiss
        @State private var adding = false
        @State private var removing: GitWorktree?
        @State private var confirmingRemoval = false

        var body: some View {
            List {
                ForEach(model.worktrees) { worktree in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(worktree.branch ?? "Detached HEAD")
                            .font(.subheadline.weight(.semibold))
                        Text(worktree.path)
                            .font(HermesFont.code)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if worktree.isMain {
                            Text("Main checkout")
                                .font(.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                        } else if worktree.locked {
                            Text("Locked")
                                .font(.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !worktree.isMain {
                            Button("Remove", role: .destructive) {
                                removing = worktree
                                confirmingRemoval = true
                            }
                        }
                    }
                }
                if let errorText = model.errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Worktrees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add worktree", systemImage: "plus") { adding = true }
                }
            }
            .task { await model.reload() }
            .sheet(isPresented: $adding) {
                GitWorktreeAddSheet(model: model)
            }
            .confirmationDialog("Remove this checkout?", isPresented: $confirmingRemoval) {
                if let worktree = removing {
                    Button("Remove", role: .destructive) {
                        Task { await model.removeWorktree(worktree, force: false) }
                    }
                    Button("Remove even with uncommitted changes", role: .destructive) {
                        Task { await model.removeWorktree(worktree, force: true) }
                    }
                }
            } message: {
                Text(removing?.path ?? "")
            }
        }
    }

    /// The form for a new linked worktree. Blank fields fall back to the server's defaults.
    private struct GitWorktreeAddSheet: View {
        let model: GitReviewModel

        @Environment(\.dismiss) private var dismiss
        @State private var name = ""
        @State private var branch = ""
        @State private var base = ""

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Folder name", text: $name)
                        TextField("New branch", text: $branch)
                        TextField("Base", text: $base)
                    } footer: {
                        Text("Without a branch, the server creates hermes/ followed by the folder name.")
                    }
                    if let errorText = model.errorText {
                        Section {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Section {
                        Button("Add worktree") { Task { await add() } }
                            .disabled(model.working)
                    }
                }
                .navigationTitle("Add worktree")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }

        private func add() async {
            let added = await model.addWorktree(
                name: gitWorktreeText(name), branch: gitWorktreeText(branch), base: gitWorktreeText(base))
            if added {
                dismiss()
            }
        }
    }

    /// A trimmed form entry, or nil when it is blank.
    private func gitWorktreeText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
#endif
