#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The Bots screen: every bot of every saved gateway in one list (plan Q7), plus the active gateway's Group Chats.
    /// Tapping a bot opens its Bot Chat; tapping a group opens the room.
    struct BotsHomeView: View {
        @Bindable var model: BotsModel
        let rooms: RoomsModel
        @State private var isCreatingPresented = false
        @State private var isCreatingGroupPresented = false
        @State private var editing: BotRosterEntry?

        /// Group creation needs room methods on the active gateway and two ready bots to join.
        private var canCreateGroup: Bool {
            rooms.supportsGroups == true && model.groupCandidates.count >= RoomDraft.minMembers
        }

        var body: some View {
            List {
                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .font(HermesFont.footnote)
                            .foregroundStyle(HermesColor.destructive)
                        Button("Dismiss") { model.errorMessage = nil }
                    }
                }
                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
                if model.query.isEmpty {
                    RoomsSection(model: rooms, showsCreate: canCreateGroup) {
                        isCreatingGroupPresented = true
                    }
                }
            }
            .navigationDestination(for: RoomRoute.self) { route in
                RoomChatScreen(model: rooms, roomID: route.roomID)
            }
            .overlay { emptyState }
            .navigationTitle("Bots")
            .modifier(OptionalSearch(isEnabled: model.showsSearch, text: $model.query))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Agent", systemImage: "plus") { isCreatingPresented = true }
                }
            }
            .refreshable {
                await model.reload()
                await rooms.reload()
            }
            .task {
                await model.reload()
                await rooms.reload()
            }
            .sheet(isPresented: $isCreatingPresented) {
                NewAgentSheet(model: model)
            }
            .sheet(isPresented: $isCreatingGroupPresented) {
                NewRoomSheet(model: rooms, candidates: model.groupCandidates)
            }
            .sheet(item: $editing) { entry in
                BotEditSheet(model: model, entry: entry)
            }
        }

        private func row(_ entry: BotRosterEntry) -> some View {
            Button {
                Task { await model.openBotChat(entry) }
            } label: {
                BotRowLabel(entry: entry, activity: model.activity(of: entry))
            }
            .disabled(entry.status != .ready)
            .contextMenu {
                if entry.status == .ready {
                    Button("Edit", systemImage: "pencil") { editing = entry }
                    Button(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin") {
                        var edit = BotEdit(entry: entry)
                        edit.isPinned.toggle()
                        Task { await model.saveEdits(of: entry, edit: edit) }
                    }
                    Button(entry.isHidden ? "Show" : "Hide", systemImage: entry.isHidden ? "eye" : "eye.slash") {
                        var edit = BotEdit(entry: entry)
                        edit.isHidden.toggle()
                        Task { await model.saveEdits(of: entry, edit: edit) }
                    }
                }
            }
        }

        @ViewBuilder
        private var emptyState: some View {
            if model.entries.isEmpty && rooms.visibleRooms.isEmpty && rooms.errorMessage == nil && !model.isLoading {
                ContentUnavailableView(
                    "No bots yet", systemImage: "person.2", description: Text("Tap + to make one."))
            }
        }
    }

    /// One bot's row: avatar, name, a line of handle and latest text, and an activity mark.
    private struct BotRowLabel: View {
        let entry: BotRosterEntry
        let activity: BotActivity

        var body: some View {
            HStack(spacing: 12) {
                BotAvatarView(name: entry.title, avatar: entry.avatar, tint: entry.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(HermesFont.headline)
                            .lineLimit(1)
                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(HermesFont.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(detail)
                        .font(HermesFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ActivityMark(activity: activity)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        private var detail: String {
            switch entry.status {
            case .ready:
                [entry.mention, entry.preview, entry.role]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .prefix(2)
                    .joined(separator: " · ")
            case .onDemand:
                "Switch to its server to chat"
            case .unavailable:
                entry.isRetained ? "Server unreachable. Showing the last known bots." : "Server unreachable"
            }
        }
    }

    /// The dot for a bot that is working or active now. Idle bots show nothing.
    private struct ActivityMark: View {
        let activity: BotActivity

        var body: some View {
            switch activity {
            case .idle:
                EmptyView()
            case .active:
                Circle()
                    .fill(HermesColor.statusConnected)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Active now")
            case .working:
                Circle()
                    .fill(HermesColor.statusWarning)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Working")
            }
        }
    }

    /// Shows the search field only when the roster needs one (WP-42 spec, section 2).
    private struct OptionalSearch: ViewModifier {
        let isEnabled: Bool
        @Binding var text: String

        func body(content: Content) -> some View {
            if isEnabled {
                content.searchable(text: $text, prompt: "Search bots")
            } else {
                content
            }
        }
    }
#endif
