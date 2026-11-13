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
