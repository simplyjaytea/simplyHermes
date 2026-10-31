#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The value a group chat row pushes. The screen it opens is `RoomChatScreen`.
    struct RoomRoute: Hashable {
        let roomID: String
    }

    /// The group chats of the Bots screen. Plan Q7 puts group rooms in the roster like group chats, so they sit in
    /// the same list as the bots. A gateway without the room methods shows nothing, and New Group appears only when
    /// the gateway can make one and two bots are ready to join it.
    struct RoomsSection: View {
        @Bindable var model: RoomsModel
        /// Whether the New Group row shows. The screen decides from the active gateway's support and its ready bots.
        var showsCreate = false
        /// Opens the New Group sheet.
        var onCreate: () -> Void = {}

        /// An empty section with no action would leave a header and nothing under it.
        private var isHidden: Bool {
            model.visibleRooms.isEmpty && !showsCreate && model.errorMessage == nil
        }

        var body: some View {
            if !isHidden, model.supportsGroups == true || model.errorMessage != nil {
                Section("Group Chats") {
                    if let message = model.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.destructive)
                            Button("Dismiss") { model.errorMessage = nil }
                                .font(HermesFont.footnote)
                        }
                    }
                    if showsCreate {
                        Button(action: onCreate) {
                            Label("New Group", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("bots.newGroup")
                    }
                    ForEach(model.visibleRooms, id: \.roomID) { room in
                        NavigationLink(value: RoomRoute(roomID: room.roomID)) {
                            RoomRowLabel(room: room, needsAttention: model.needsAttention(room))
                        }
                    }
                }
            }
        }
    }

    /// The chat a group row pushes. A room the list no longer has shows a placeholder.
    struct RoomChatScreen: View {
        let model: RoomsModel
        let roomID: String

        var body: some View {
            if let chat = model.chat(forRoomID: roomID) {
                RoomChatView(model: chat)
            } else {
                ContentUnavailableView("Group Chat not found", systemImage: "person.3")
            }
        }
    }

    /// One group chat's row: its name, how many bots it has, and a badge when it waits on the user.
    struct RoomRowLabel: View {
        let room: Room
        let needsAttention: Bool

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(HermesColor.accent)
                    .frame(width: 32, height: 32)
                    .background(HermesColor.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(HermesFont.headline)
                    Text("\(room.members.count) bots")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Spacer(minLength: 8)
                if needsAttention {
                    Text("Needs you")
                        .font(HermesFont.caption2.weight(.semibold))
                        .foregroundStyle(HermesColor.statusWarning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(HermesColor.statusWarning.opacity(0.15), in: Capsule())
                }
            }
        }
    }
#endif
