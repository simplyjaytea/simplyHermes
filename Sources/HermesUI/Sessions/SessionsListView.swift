#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Chats list: time sections with pinned chats first, swipe to pin, archive or delete, pull to refresh,
    /// and search (WP-40).
    public struct SessionsListView: View {
        @Bindable private var model: SessionsListModel
        private let onOpen: (SessionListItem) -> Void
        /// Whether a chat waits on an approval, by session id. Marks its row with a dot.
        private let needsApproval: (String) -> Bool
        @State private var pendingDelete: SessionListItem?

        public init(
            model: SessionsListModel,
            needsApproval: @escaping (String) -> Bool = { _ in false },
            onOpen: @escaping (SessionListItem) -> Void
        ) {
            self.model = model
            self.needsApproval = needsApproval
            self.onOpen = onOpen
        }

        public var body: some View {
            List {
                if let errorText = model.errorText {
                    Label(errorText, systemImage: "wifi.slash")
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .accessibilityIdentifier("sessions.error")
                }
                if model.isSearching {
                    searchResults
                } else {
                    ForEach(model.sections) { section in
                        Section(section.group.title) {
                            ForEach(section.items) { item in row(item) }
                        }
                    }
                }
            }
            .searchable(text: $model.searchText, prompt: "Search chats")
            .refreshable { await model.refresh() }
            .task(id: model.searchText) { await model.runSearch() }
            .overlay {
                if model.sections.isEmpty && !model.isSearching && !model.isRefreshing {
                    ContentUnavailableView(
                        "No chats yet", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a chat and it shows up here."))
                }
            }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible, presenting: pendingDelete
            ) { item in
                Button("Delete", role: .destructive) { Task { await model.delete(item.id) } }
            } message: { item in
                Text("\"\(item.title)\" is deleted from the server. This cannot be undone.")
            }
        }

        @ViewBuilder
        private var searchResults: some View {
            ForEach(model.searchHits) { hit in
                Button {
                    onOpen(
                        SessionListItem(
                            id: hit.sessionId, title: hit.title ?? "Untitled chat", time: nil, isPinned: false,
                            serverName: ""))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title ?? "Untitled chat")
                            .font(HermesFont.body.weight(.semibold))
                            .lineLimit(1)
                        if let snippet = hit.snippet {
                            Text(
                                snippet.replacingOccurrences(of: ">>>", with: "").replacingOccurrences(
                                    of: "<<<", with: "")
                            )
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(2)
                        }
                    }
                }
                .tint(HermesColor.primaryText)
            }
        }

        private func row(_ item: SessionListItem) -> some View {
            Button {
                onOpen(item)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(HermesFont.body.weight(.semibold))
                            .lineLimit(1)
                        Text(item.serverName)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .lineLimit(1)
                    }
                    if needsApproval(item.id) {
                        ApprovalDot()
                    }
                    Spacer(minLength: 8)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                            .accessibilityLabel("Pinned")
                    }
                    if let time = item.time {
                        Text(time)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session.\(item.id)")
            }
            .tint(HermesColor.primaryText)
            .swipeActions(edge: .leading) {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    Task { await model.togglePin(item.id) }
                }
                .tint(HermesColor.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                Button("Archive", systemImage: "archivebox") { Task { await model.archive(item.id) } }
                    .tint(HermesColor.statusWarning)
            }
        }
    }
#endif
