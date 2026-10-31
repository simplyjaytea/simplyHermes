#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The group chats of the active gateway, and the open chat for each (WP-43). A gateway without the room methods
    /// shows none.
    @MainActor
    @Observable
    final class RoomsModel {
        private(set) var rooms: [Room] = []
        private(set) var isLoading = false
        /// Whether the active gateway has the room methods. Nil until a read answers, so New Group does not show
        /// before the app knows the gateway can make one.
        private(set) var supportsGroups: Bool?
        /// The last failure, shown above the list. Nil once a reload works.
        var errorMessage: String?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private var client: RoomClient?
        @ObservationIgnored private var capabilities: GroupsCapabilitiesResult?
        @ObservationIgnored private var connectionID: UUID?
        /// One open chat per room, kept so a chat keeps its transcript while it is pushed.
        @ObservationIgnored private var chats: [String: RoomChatModel] = [:]

        init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// The rooms the list draws: every room read from the gateway, minus the ones disbanded here.
        var visibleRooms: [Room] {
            rooms.filter { chats[$0.roomID]?.isDisbanded != true }
        }

        /// Whether a room waits on the user, because an approval is pending. Only a room whose chat is open is current.
        func needsAttention(_ room: Room) -> Bool {
            RoomStatus.pendingApproval(in: chats[room.roomID]?.status) != nil
        }

        /// Reads the rooms on the active gateway. Rooms homed on another gateway do not appear (WP-43 spec, section 5).
        func reload() async {
            guard let manager = connections.manager, let connection = connections.active else {
                client = nil
                capabilities = nil
                chats = [:]
                connectionID = nil
                rooms = []
                supportsGroups = nil
                errorMessage = nil
                return
            }
            if connectionID != connection.id {
                // Another gateway is active. Its client and rooms go before the first await, so a failed read
                // cannot leave them on screen or let a chat keep polling it.
                client = nil
                capabilities = nil
                chats = [:]
                rooms = []
                supportsGroups = nil
                errorMessage = nil
                connectionID = connection.id
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let gateway = try await manager.client(for: connection)
                let roomClient = RoomClient(gateway: gateway)
                let caps = try await roomClient.capabilities()
                client = roomClient
                capabilities = caps
                rooms = try await roomClient.rooms()
                supportsGroups = true
                errorMessage = nil
            } catch let error as RPCError where error.code == -32601 {
                // The gateway has no room methods, so it hosts no group chats.
                client = nil
                capabilities = nil
                chats = [:]
                rooms = []
                supportsGroups = false
                errorMessage = nil
            } catch {
                errorMessage = RoomFailure.message(for: error)
            }
        }

        /// The open chat for a room, made on first use.
        func chat(for room: Room) -> RoomChatModel? {
            guard let client else { return nil }
            if let open = chats[room.roomID] {
                return open
            }
            let chat = RoomChatModel(room: room, client: client, capabilities: capabilities)
            chats[room.roomID] = chat
            return chat
        }

        /// The open chat for a room id, for the screen a list row pushes.
        func chat(forRoomID roomID: String) -> RoomChatModel? {
            if let open = chats[roomID] {
                return open
            }
            guard let room = rooms.first(where: { $0.roomID == roomID }) else { return nil }
            return chat(for: room)
        }

        /// Makes a group chat on the active gateway. Keep `roomID` from before the first try: the server answers a repeat
        /// with the same room.
        func create(_ draft: RoomDraft, roomID: String) async throws -> Room {
            guard let client else { throw RoomError.noGateway }
            let room = try await client.create(draft, roomID: roomID)
            // Show the room even if the list read after it fails; the next refresh reads it again.
            if !rooms.contains(where: { $0.roomID == room.roomID }) {
                rooms.insert(room, at: 0)
            }
            await reload()
            return room
        }
    }
#endif
