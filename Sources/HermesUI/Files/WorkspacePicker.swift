#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The folder a chat runs in, as a glass pill under the chat header. Tapping it opens the picker (WP-37).
    struct WorkspacePill: View {
        let folder: String?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(Self.name(of: folder), systemImage: "folder")
                    .font(HermesFont.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: HermesMetrics.minTapTarget - 8)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Capsule())
            .accessibilityIdentifier("chat.workspace")
            .accessibilityHint(Text("Chooses the folder this chat runs in"))
        }

        /// The last part of the path, which is what the pill has room for.
        static func name(of folder: String?) -> String {
            guard let folder, !folder.isEmpty else { return "Choose folder" }
            return URL(fileURLWithPath: folder).lastPathComponent
        }
    }

    /// The folders the server offers. Picking one moves the chat there and closes the sheet (WP-37).
    struct WorkspacePickerSheet: View {
        @Bindable var browser: WorkspaceBrowserModel
        /// The folder the chat runs in now, which gets a checkmark.
        let current: String?
        /// Moves the chat. Returns false when the server refuses, and the sheet stays open.
        let onPick: @MainActor (String) async -> Bool
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if let list = browser.workspaces {
                        ForEach(list.projects + list.repos) { root in
                            Button {
                                Task {
                                    if await onPick(root.root) { dismiss() }
                                }
                            } label: {
                                row(root)
                            }
                            .accessibilityIdentifier("workspace.\(root.id)")
                        }
                    }
                    if let notice = browser.notice {
                        Text(notice)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
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
            .task { await browser.load() }
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
                if root.root == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(HermesColor.accent)
                }
            }
            .frame(minHeight: HermesMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
    }
#endif
