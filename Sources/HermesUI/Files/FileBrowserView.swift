#if canImport(UIKit)
    import HermesKit
    import QuickLook
    import SwiftUI

    /// The read-only file browser in the preview rail: folders first, then text files (WP-37).
    struct FileBrowserView: View {
        @Bindable var browser: WorkspaceBrowserModel
        /// Gets the path of a file the user adds to the chat.
        let onAddToChat: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                header
                if let notice = browser.notice {
                    Text(notice)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                List(browser.entries) { entry in
                    Button {
                        Task { await browser.select(entry) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                                .foregroundStyle(HermesColor.secondaryText)
                            Text(entry.name)
                                .font(HermesFont.body)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: HermesMetrics.minTapTarget - 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // QuickLook has no Add to chat, so every file offers it here.
                    .contextMenu {
                        if !entry.isDirectory {
                            Button("Add to chat") { onAddToChat(entry.path) }
                        }
                    }
                    .accessibilityIdentifier("file.\(entry.id)")
                }
                .listStyle(.plain)
            }
            .task(id: browser.loadKey) { await browser.load() }
            .quickLookPreview(
                Binding(get: { browser.quickLookURL }, set: { if $0 == nil { browser.closeQuickLook() } })
            )
            .sheet(isPresented: Binding(get: { browser.preview != nil }, set: { if !$0 { browser.closePreview() } })) {
                if let file = browser.preview {
                    FilePreviewSheet(file: file) {
                        onAddToChat(file.path)
                        browser.closePreview()
                    }
                }
            }
        }

        private var header: some View {
            HStack(spacing: 8) {
                Button {
                    Task { await browser.up() }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(browser.folder == nil || browser.folder == "/")
                .accessibilityLabel(Text("Up one folder"))
                Text(browser.folder ?? String(localized: "No folder"))
                    .font(HermesFont.code)
                    .foregroundStyle(HermesColor.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    /// A text file from the server, with Add to chat. Binary files open in QuickLook instead (WP-37).
    private struct FilePreviewSheet: View {
        let file: FsText
        let onAddToChat: () -> Void
        @Environment(\.dismiss) private var dismiss

        /// The most characters drawn. The server may send megabytes, and one `Text` that long freezes the rail.
        private static let characterLimit = 20_000

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(shownText)
                            .font(HermesFont.code)
                            .foregroundStyle(file.text == nil ? HermesColor.secondaryText : HermesColor.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isCut {
                            Text("Showing the first \(Self.characterLimit) characters.")
                                .font(HermesFont.caption)
                                .foregroundStyle(HermesColor.secondaryText)
                        }
                    }
                    .padding()
                }
                .navigationTitle(URL(fileURLWithPath: file.path).lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add to chat", action: onAddToChat)
                    }
                }
            }
        }

        /// The start of the text, or why there is none.
        private var shownText: String {
            guard let text = file.text else { return String(localized: "This file has no text to show.") }
            return String(text.prefix(Self.characterLimit))
        }

        /// True when the text is longer than what is drawn.
        private var isCut: Bool {
            guard let text = file.text else { return false }
            return !text.dropFirst(Self.characterLimit).isEmpty
        }
    }
#endif
