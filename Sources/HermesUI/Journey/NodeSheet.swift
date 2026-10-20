#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The sheet of one node (WP-52): read its text, rewrite it, or delete it.
    ///
    /// Deleting asks first, and the question says what really happens: a skill is archived on the server and a memory
    /// is removed for good. A pinned skill cannot be deleted, so the sheet says why instead of offering the button.
    struct NodeSheet: View {
        @Bindable var editor: NodeEditorModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                content
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
                    .safeAreaInset(edge: .bottom, spacing: 0) { deleteBar }
            }
            .task { await editor.load() }
            .interactiveDismissDisabled(isWorking || editor.hasChanges)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .accessibilityIdentifier("node.sheet")
        }

        /// A memory chunk is named by its first line, which is too long for a title, so it gets its kind instead.
        private var title: String {
            editor.node.kind == .memory ? editor.node.kindTitle : editor.node.label
        }

        /// The server is busy with a change, so the sheet stays open until it answers.
        private var isWorking: Bool {
            editor.phase == .saving || editor.phase == .deleting
        }

        /// The facts under the title: kind, category, who wrote it, how often it was used, and when it was touched.
        private var facts: String {
            var parts = editor.node.detailParts
            if let date = editor.node.date {
                parts.append("Last touched \(date.formatted(date: .abbreviated, time: .omitted))")
            }
            return parts.joined(separator: " \u{00B7} ")
        }

        // MARK: Content

        @ViewBuilder
        private var content: some View {
            switch editor.phase {
            case .loading:
                ProgressView("Loading\u{2026}")
                    .accessibilityIdentifier("node.loading")
            case .failed(let reason):
                ContentUnavailableView {
                    Label("Could not open this node", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                } actions: {
                    Button("Try again") { Task { await editor.load() } }
                        .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                        .accessibilityIdentifier("node.retry")
                }
                .accessibilityIdentifier("node.failed")
            case .viewing, .deleting:
                reading
            case .editing, .saving:
                editing
            }
        }

        private var reading: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(facts)
                        .font(HermesFont.subheadline)
                        .foregroundStyle(HermesColor.secondaryText)
                    Text(editor.content.isEmpty ? "This node has no text." : editor.content)
                        .font(HermesFont.code)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("node.content")
                    problem
                }
                .padding(16)
            }
        }

        private var editing: some View {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $editor.draft)
                    .font(HermesFont.code)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        HermesColor.fill,
                        in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous)
                    )
                    .disabled(editor.phase == .saving)
                    .accessibilityLabel("Text of \(title)")
                    .accessibilityIdentifier("node.editor")
                problem
            }
            .padding(16)
        }

        /// Why the last save or delete failed. The typed text stays, so nothing is lost.
        @ViewBuilder
        private var problem: some View {
            if let text = editor.problem {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.destructive)
                    .accessibilityIdentifier("node.problem")
            }
        }

        // MARK: Toolbar

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .cancellationAction) {
                if editor.isEditing {
                    Button("Cancel") { editor.cancelEditing() }
                        .disabled(isWorking)
                        .accessibilityIdentifier("node.cancel")
                } else {
                    Button("Close") { dismiss() }
                        .disabled(isWorking)
                        .accessibilityIdentifier("node.close")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if editor.isEditing {
                    saveButton
                } else {
                    Button("Edit") { editor.beginEditing() }
                        .disabled(!editor.canEdit)
                        .accessibilityIdentifier("node.edit")
                }
            }
        }

        @ViewBuilder
        private var saveButton: some View {
            if editor.phase == .saving {
                ProgressView().accessibilityLabel("Saving")
            } else {
                Button("Save") { Task { await editor.save() } }
                    .disabled(!editor.canSave)
                    .accessibilityIdentifier("node.save")
            }
        }

        // MARK: Delete

        @ViewBuilder
        private var deleteBar: some View {
            if !editor.isEditing {
                VStack(spacing: 8) {
                    if let blocker = editor.node.deleteBlocker {
                        Label(blocker, systemImage: "pin.fill")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityIdentifier("node.blocker")
                    }
                    deleteButton
                }
                .padding(16)
                .background(.bar)
            }
        }

        private var deleteButton: some View {
            Button(role: .destructive) {
                editor.requestDelete()
            } label: {
                if editor.phase == .deleting {
                    ProgressView().tint(HermesColor.onAccent).accessibilityLabel("Deleting")
                } else {
                    Text("Delete")
                }
            }
            .buttonStyle(HermesButtonStyle(.destructive))
            .disabled(!editor.canDelete)
            .accessibilityIdentifier("node.delete")
            .confirmationDialog(
                editor.node.deleteTitle, isPresented: $editor.confirmsDelete, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await editor.delete() } }
                    .accessibilityIdentifier("node.confirmDelete")
            } message: {
                Text(editor.node.deleteMessage)
            }
        }
    }
#endif
