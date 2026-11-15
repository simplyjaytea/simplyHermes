#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Chats list: time sections with pinned chats first, swipe and menu actions for each chat, pull to refresh,
    /// search (WP-40), and a menu that prunes old sessions. Chats whose message is not sent yet, and that the server
    /// does not list, come first under "Waiting to send".
    public struct SessionsListView: View {
        @Bindable private var model: SessionsListModel
        private let onOpen: (SessionListItem) -> Void
        /// Whether a chat waits on an approval, by session id. Marks its row with a dot.
        private let needsApproval: (String) -> Bool
        /// The chats with a message not sent yet that the server does not list. Shown first, with a clock mark.
        private let waiting: [SessionListItem]
        private let onOpenWaiting: (String) -> Void
        @State private var isPruneSheetPresented = false
        @Environment(\.hermesPalette) private var palette

        public init(
            model: SessionsListModel,
            needsApproval: @escaping (String) -> Bool = { _ in false },
            waiting: [SessionListItem] = [],
            onOpenWaiting: @escaping (String) -> Void = { _ in },
            onOpen: @escaping (SessionListItem) -> Void
        ) {
            self.model = model
            self.needsApproval = needsApproval
            self.waiting = waiting
            self.onOpenWaiting = onOpenWaiting
            self.onOpen = onOpen
        }

        public var body: some View {
            List {
                if let errorText = model.errorText {
                    Label(errorText, systemImage: "wifi.slash")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("sessions.error")
                }
                if let noticeText = model.noticeText {
                    Label(noticeText, systemImage: "checkmark.circle")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("sessions.notice")
                }
                if model.isSearching {
                    searchResults
                } else {
                    if !waiting.isEmpty {
                        Section("Waiting to send") {
                            ForEach(waiting) { item in waitingRow(item) }
                        }
                        .listRowBackground(palette.card)
                    }
                    ForEach(model.visibleSections) { section in
                        Section(section.group.title) {
                            ForEach(section.items) { item in row(item) }
                        }
                        .listRowBackground(palette.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .toolbarBackground(palette.groupedBackground, for: .navigationBar)
            .searchable(text: $model.searchText, isPresented: $model.isSearchPresented, prompt: "Search chats")
            .refreshable { await model.refresh() }
            .task(id: model.searchText) { await model.runSearch() }
            .overlay {
                if model.visibleSections.isEmpty && waiting.isEmpty && !model.isSearching && !model.isRefreshing {
                    ContentUnavailableView(
                        "No chats yet", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a chat and it shows up here."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Prune old sessions…", systemImage: "trash.slash") {
                            isPruneSheetPresented = true
                        }
                        .accessibilityIdentifier("sessions.prune")
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("Chat list options")
                    .accessibilityIdentifier("sessions.menu")
                }
            }
            .sheet(isPresented: $isPruneSheetPresented) {
                PruneSessionsSheet(model: model)
            }
            .sheet(item: $model.exportedChat) { chat in
                ExportedChatSheet(chat: chat)
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
                            .accessibleLineLimit()
                        if let snippet = hit.snippet {
                            Text(
                                snippet.replacingOccurrences(of: ">>>", with: "").replacingOccurrences(
                                    of: "<<<", with: "")
                            )
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                        }
                    }
                }
                .tint(palette.primaryText)
            }
        }

        private func waitingRow(_ item: SessionListItem) -> some View {
            Button {
                onOpenWaiting(item.id)
            } label: {
                AccessibleHStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(HermesFont.body.weight(.semibold))
                            .accessibleLineLimit()
                        Text(item.serverName)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .accessibleLineLimit()
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "clock")
                        .font(HermesFont.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityLabel("Waiting to send")
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session.\(item.id)")
            }
            .tint(palette.primaryText)
        }

        private func row(_ item: SessionListItem) -> some View {
            Button {
                onOpen(item)
            } label: {
                AccessibleHStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(HermesFont.body.weight(.semibold))
                            .accessibleLineLimit()
                        Text(item.serverName)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .accessibleLineLimit()
                    }
                    if needsApproval(item.id) {
                        ApprovalDot()
                    }
                    Spacer(minLength: 8)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .accessibilityLabel("Pinned")
                    }
                    if let time = item.time {
                        Text(time)
                            .font(HermesFont.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session.\(item.id)")
            }
            .tint(palette.primaryText)
            .contextMenu {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    Task { await model.togglePin(item.id) }
                }
                if item.link != nil {
                    Button("Copy link", systemImage: "link") { model.copyLink(item) }
                }
                Button("Export", systemImage: "square.and.arrow.up") { Task { await model.export(item) } }
                Button("Archive", systemImage: "archivebox") { Task { await model.archive(item.id) } }
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete(item.id) } }
                    .accessibilityIdentifier("session.delete")
            }
            .swipeActions(edge: .leading) {
                Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                    Task { await model.togglePin(item.id) }
                }
                .tint(palette.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete(item.id) } }
                    .accessibilityIdentifier("session.delete")
                Button("Archive", systemImage: "archivebox") { Task { await model.archive(item.id) } }
                    .tint(palette.statusWarning)
                Button("Export", systemImage: "square.and.arrow.up") { Task { await model.export(item) } }
                    .tint(palette.accent)
            }
        }
    }
#endif
