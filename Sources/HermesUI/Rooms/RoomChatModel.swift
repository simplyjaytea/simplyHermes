#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One group chat on screen: its transcript, the driver's state, and the sends, stops and answers the screen makes
    /// (WP-43 spec, sections 2 to 6).
    @MainActor
    @Observable
    final class RoomChatModel {
        private(set) var room: Room
        private(set) var rows: [RoomRow] = []
        private(set) var status: RoomDriverStatus?
        private(set) var isSending = false
        /// The newest read failure, shown above the composer. Nil once a read works.
        var errorMessage: String?
        /// The newest failure of a send, stop, answer or retry. Only the next action that works clears it, so a read
        /// does not hide it.
        var actionError: String?
        /// What the composer holds. The mention picker and the slash guard read it.
        var draft = ""
        /// The last send that failed. Sending the same text again reuses its ids, so the server stores it once.
        private(set) var outgoing: RoomOutgoingMessage?

        @ObservationIgnored private let client: RoomClient
        @ObservationIgnored private let capabilities: GroupsCapabilitiesResult?
        @ObservationIgnored private var transcript = RoomTranscript()
        @ObservationIgnored private var labels: [String: String] = [:]
        /// When this screen last sent, so reads run quickly for a short while after a send.
        @ObservationIgnored private var lastSendAt: Date?

        init(room: Room, client: RoomClient, capabilities: GroupsCapabilitiesResult?) {
            self.room = room
            self.client = client
            self.capabilities = capabilities
            labels = RoomTimeline.labels(for: room)
        }

        var isDisbanded: Bool {
            room.disbandedAt != nil
        }

        /// Why the composer is shut, or nil when the room takes messages here.
        var readOnlyNote: String? {
            room.readOnlyNote(on: capabilities)
        }

        /// The handles the mention picker offers after the broadcasts.
        var handles: [String] {
            room.members.compactMap(\.handle)
        }

        /// The mention under the caret. The caret is taken to be at the end of the draft.
        var completion: RoomCompletion? {
            RoomMentions.completion(in: draft, caret: draft.endIndex)
        }

        func profile(forMember memberID: String) -> String? {
            room.members.first { $0.memberID == memberID }?.profile
        }

        func label(forMember memberID: String) -> String {
            labels[memberID] ?? memberID
        }

        /// Reads the room until it is disbanded or the screen goes away. The pause between reads comes from the status.
        func run() async {
            while !Task.isCancelled, !isDisbanded {
                await refresh()
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }

        /// The state, then the events after the cursor. A failure shows above the composer, and the transcript stays.
        func refresh() async {
            do {
                let state = try await client.state(roomID: room.roomID)
                room = state.room
                status = state.driverStatus
                labels = RoomTimeline.labels(for: room)
                let log = try await client.log(roomID: room.roomID, since: transcript.cursor)
                transcript.merge(log)
                rows = transcript.rows(labels: labels)
                errorMessage = nil
            } catch let error as RPCError where error.code == 4112 {
                // The cursor is ahead of the log, so the next read starts from the top.
                transcript.reset()
                rows = []
            } catch {
                errorMessage = RoomFailure.message(for: error)
            }
        }

        /// Sends the draft. A send that fails keeps its ids, so sending the same text again is the same message.
        func send() async {
            guard !isSending, readOnlyNote == nil else { return }
            let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let message: RoomOutgoingMessage
            if let outgoing, outgoing.text == typed {
                message = outgoing
            } else if let fresh = RoomOutgoingMessage(text: typed) {
                message = fresh
            } else {
                return
            }
            outgoing = message
            isSending = true
            do {
                let result = try await client.send(
                    roomID: room.roomID, eventID: message.eventID, text: message.text, threadID: message.threadID)
                if result.accepted {
                    outgoing = nil
                    draft = ""
                    lastSendAt = Date()
                    actionError = result.driverStarted ? nil : "Message saved; the room did not start a turn."
                } else {
                    // Keep the draft and ids, so trying again is the same message.
                    actionError = "The room did not accept the message. Try again."
                }
            } catch {
                actionError = RoomFailure.message(for: error)
            }
            isSending = false
            await refresh()
        }

        /// Stops every running turn. Each tap gets its own cancel id (WP-43 spec, section 4).
        func stop() async {
            guard readOnlyNote == nil else { return }
            do {
                _ = try await client.stop(roomID: room.roomID, cancelID: RoomIdentifier.newCancelID())
                actionError = nil
            } catch {
                actionError = RoomFailure.message(for: error)
            }
            await refresh()
        }

        /// Answers an approval the room waits on.
        func answer(_ action: RoomPendingAction, with choice: RoomApprovalChoice) async {
            guard readOnlyNote == nil else { return }
            do {
                try await client.approve(roomID: room.roomID, action: action, choice: choice)
                actionError = nil
            } catch {
                actionError = RoomFailure.message(for: error)
            }
            await refresh()
        }

        /// Runs a task again. Call only after the user confirms, since the room may already have run part of it.
        func retry(_ action: RoomPendingAction) async {
            guard readOnlyNote == nil else { return }
            do {
                _ = try await client.retry(roomID: room.roomID, taskID: action.taskID)
                actionError = nil
            } catch {
                actionError = RoomFailure.message(for: error)
            }
            await refresh()
        }

        /// Renames the room. Each rename gets its own event id, so a repeat of the same rename is harmless.
        func rename(to name: String) async throws {
            guard readOnlyNote == nil else { throw RoomError.readOnly }
            room = try await client.rename(roomID: room.roomID, eventID: RoomIdentifier.newEventID(), to: name)
        }

        /// Disbands the room. It stops running turns first, and it leaves the list.
        func disband() async throws {
            guard readOnlyNote == nil else { throw RoomError.readOnly }
            let tombstone = try await client.disband(roomID: room.roomID)
            room.disbandedAt = tombstone.disbandedAt
        }

        private var pollInterval: TimeInterval {
            if let lastSendAt, Date().timeIntervalSince(lastSendAt) < 10 {
                return 1
            }
            return RoomStatus.pollInterval(for: status)
        }
    }
#endif
