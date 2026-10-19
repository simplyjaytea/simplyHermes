#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The folders the server offers. Picking one moves the chat there and closes the sheet (WP-37).
    struct WorkspacePickerSheet: View {
        @Bindable var browser: WorkspaceBrowserModel
        /// The folder the chat runs in now, which gets a checkmark.
        let current: String?
        /// Moves the chat. Returns why the server refused, or nil when it moved. The sheet stays open on a refusal.
        let onPick: @MainActor (String) async -> String?
        @Environment(\.dismiss) private var dismiss
        /// The folder a move is running for. The rows are off until the server answers, so taps cannot overlap.
        @State private var moving: String?
        /// Why the last read of the list or the last move failed.
        @State private var failure: String?

        var body: some View {
            NavigationStack {
                List {
                    ForEach(roots) { root in
                        Button {
                            pick(root)
                        } label: {
                            row(root)
                        }
                        .disabled(moving != nil)
                        .accessibilityIdentifier("workspace.\(root.id)")
                        .accessibilityAddTraits(root.root == current ? .isSelected : [])
                    }
                    if let failure {
                        Text(failure)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
                .navigationTitle("Workspace")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            // Read again on every open, so folders that came or went on the server show up.
            .task { failure = await browser.refreshWorkspaces() }
        }

        /// Projects, then repos. A folder that is both shows once.
        private var roots: [WorkspaceRoot] {
            guard let list = browser.workspaces else { return [] }
            var seen = Set<String>()
            return (list.projects + list.repos).filter { seen.insert($0.root).inserted }
        }

        private func pick(_ root: WorkspaceRoot) {
            guard moving == nil else { return }
            moving = root.root
            failure = nil
            Task {
                let refusal = await onPick(root.root)
                moving = nil
                if let refusal { failure = refusal } else { dismiss() }
            }
        }

        private func row(_ root: WorkspaceRoot) -> some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(root.label ?? URL(fileURLWithPath: root.root).lastPathComponent)
                        .font(HermesFont.body)
                    Text(root.root)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                if root.root == moving {
                    ProgressView().controlSize(.small)
                } else if root.root == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HermesColor.accent)
                }
            }
            .frame(minHeight: HermesMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
    }
#endif
