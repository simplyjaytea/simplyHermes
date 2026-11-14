#if canImport(UIKit)
    import HermesKit

    /// A New chat's first message through the queue (board row 104): it is saved before anything is tried, waits for its
    /// own server, and goes out once. Kept apart from ``ShellModel`` so that class stays readable.
    extension ShellModel {
        /// Saves the draft as the chat's first message and lets the queue deliver it. The draft is cleared only after the
        /// message is saved. A repeat send in the same chat joins the one in flight, so a double tap saves one message.
        func queueFirstMessage(in id: String, using queue: NewChatQueue) -> Task<Void, Never>? {
            if let running = startingChats[id] { return running }
            let typed = drafts[id, default: ""]
            guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            newChatError = nil
            let task: Task<Void, Never> = Task {
                defer { self.startingChats[id] = nil }
                do {
                    try await queue.send(typed, forRow: id)
                    if self.drafts[id] == typed { self.drafts[id] = nil }
                } catch {
                    self.newChatError = "Couldn't save your message, so nothing was sent."
                }
            }
            startingChats[id] = task
            return task
        }

        /// The chat of a placeholder row now exists on the server. The row, tab, transcript and draft move to it.
        func adoptQueuedChat(row: String, sessionID: String, serverName: String) {
            adopt(
                SessionListItem(id: sessionID, title: "New chat", time: "Now", isPinned: false, serverName: serverName),
                replacing: row)
        }

        /// The chat of a placeholder row was made on a server that is not the active one. The row goes: under another
        /// server it would be listed there with this server's session id, and opening it would aim its message at the
        /// wrong server. Its message stays in the outbox, and ``showUnsentChats(_:serverName:)`` brings the chat back
        /// when its own server is active.
        func dropQueuedRow(_ row: String) {
            unstartedChatIDs.remove(row)
            sessions.removeAll { $0.id == row }
            openSessionIDs.removeAll { $0 == row }
            closedSessionIDs.removeAll { $0 == row }
            if selectedSessionID == row { selectedSessionID = openSessionIDs.last }
            transcripts[row] = nil
        }

        /// A queued chat now exists on the server `connectionID`. When that is the active server its row is adopted
        /// and the chat attaches now, so the waiting message goes out even when the chat is not on screen. Otherwise
        /// the row is dropped. Returns whether it was adopted.
        @discardableResult
        func queuedChatCreated(
            row: String, sessionID: String, serverName: String, on connectionID: String, active: String?
        ) -> Bool {
            guard active == connectionID else {
                dropQueuedRow(row)
                return false
            }
            adoptQueuedChat(row: row, sessionID: sessionID, serverName: serverName)
            Task { await liveChats?.chat(for: sessionID)?.attach() }
            return true
        }

        /// Reads the active server's unsent chats from the outbox and lists them (``showUnsentChats(_:serverName:)``).
        func showUnsentChats(of connections: ConnectionsModel?) async {
            guard let active = connections?.active else { return }
            let ids = (try? await OutboxServices.store.unsentServerChatIDs(connection: active.id.uuidString)) ?? []
            // The read can outlast a server switch. These rows belong to the server that was read.
            guard connections?.active?.id == active.id else { return }
            showUnsentChats(ids, serverName: active.name)
        }

        /// Lists the active server's chats that hold a message not sent yet and that the list does not show. The
        /// server lists a chat only once it holds a message, so without this such a chat has no row after a relaunch
        /// or a switch back to its server, and its message waits where nobody sees it. A chat the server lists later
        /// takes the row over (``startedChatsToKeep(listed:)``).
        func showUnsentChats(_ ids: [String], serverName: String) {
            for id in ids where session(id: id) == nil {
                startedChats.note(id)
                serverSessionIDs.insert(id)
                sessions.insert(
                    ChatSessionSummary(id: id, title: "New chat", subtitle: "Waiting to send", serverName: serverName),
                    at: 0)
                transcripts[id] = []
            }
        }

        /// Puts the placeholders that were saved before a relaunch back in the list, each with its waiting message.
        func restoreQueuedChats(_ chats: [PlaceholderChat]) {
            for chat in chats where session(id: chat.id) == nil {
                sessions.append(
                    ChatSessionSummary(
                        id: chat.id, title: "New chat", subtitle: "Waiting to send", serverName: chat.serverName))
                transcripts[chat.id] = []
                unstartedChatIDs.insert(chat.id)
            }
        }
    }
#endif
