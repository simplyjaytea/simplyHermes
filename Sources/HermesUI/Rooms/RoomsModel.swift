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
        /// The last read driver status for each room, so the list can show an approval before the room is opened.
        private(set) var statuses: [String: RoomDriverStatus] = [:]
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

        /// Whether a room waits on the user, because an approval is pending. The list polls the room's state; opening
        /// the room is not required.
        func needsAttention(_ room: Room) -> Bool {
            RoomStatus.pendingApproval(in: statuses[room.roomID]) != nil
        }

        /// Reads the driver state of the rooms the list draws. A failure for one room leaves its last status alone;
        /// the list is not the place for a poll error.
        func refreshStatuses() async {
            guard let client else { return }
            let visibleIDs = Set(visibleRooms.map(\.roomID))
            var fresh = statuses.filter { visibleIDs.contains($0.key) }
            for room in visibleRooms {
                guard !Task.isCancelled else { return }
                if let state = try? await client.state(roomID: room.roomID) {
                    fresh[room.roomID] = state.driverStatus
                }
            }
            statuses = fresh
        }

        /// Refreshes the room list's status while the Bots screen is visible. The task is cancelled when the screen
        /// goes away, so rooms are not polled from the shell.
        func monitorStatuses() async {
            while !Task.isCancelled {
                await refreshStatuses()
                try? await Task.sleep(for: .seconds(5))
            }
        }

        /// Reads the rooms on the active gateway. Rooms homed on another gateway do not appear (WP-43 spec, section 5).
        func reload() async {
            guard let manager = connections.manager, let connection = connections.active else {
                client = nil
                capabilities = nil
                chats = [:]
                connectionID = nil
                rooms = []
                statuses = [:]
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
                statuses = [:]
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
                statuses = statuses.filter { roomID, _ in rooms.contains { $0.roomID == roomID } }
                supportsGroups = true
                errorMessage = nil
            } catch let error as RPCError where error.code == -32601 {
                // The gateway has no room methods, so it hosts no group chats.
                client = nil
                capabilities = nil
                chats = [:]
                rooms = []
                statuses = [:]
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
