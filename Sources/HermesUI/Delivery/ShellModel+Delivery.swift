#if canImport(UIKit)
    import HermesKit

    /// What Siri, Shortcuts, Control Center and the Live Activity buttons need from the shell: which turns run, which
    /// approvals wait, and a way to stop or answer them. Each works for placeholder chats and for server chats.
    extension ShellModel {
        /// Chats with a turn running now, in sidebar order.
        public var runningSessionIDs: [String] {
            sessions.map(\.id).filter { isStreaming($0) || liveChats?.existingChat(for: $0)?.isRunning == true }
        }

        /// Every approval that waits for an answer, in sidebar order. A chat can hold more than one.
        public var allPendingApprovals: [ApprovalAlert] {
            sessions.flatMap { session -> [ApprovalAlert] in
                if let chat = liveChats?.existingChat(for: session.id), !chat.approvals.isEmpty {
                    return chat.approvals.map {
                        ApprovalAlert(
                            id: $0.id, sessionID: session.id, sessionTitle: session.title, command: $0.command)
                    }
                }
                guard let approval = pendingApproval(in: session.id) else { return [] }
                return [
                    ApprovalAlert(
                        id: approval.id, sessionID: session.id, sessionTitle: session.title, command: approval.text)
                ]
            }
        }

        /// Stops the running turn of a chat, whether it is a placeholder stream or a server turn.
        public func stopTurn(in id: String) {
            stop(in: id)
            if let chat = liveChats?.existingChat(for: id), chat.isRunning {
                chat.stop()
            }
        }

        /// Approves or denies the first approval a chat waits on.
        public func answerApproval(in id: String, approved: Bool) {
            guard let alert = allPendingApprovals.first(where: { $0.sessionID == id }) else { return }
            answer(alert, approved: approved)
        }

        /// Shows a chat the server just made, as the chat list would, and opens it. Returns the chat's id.
        ///
        /// The server lists a chat once it holds a message, so the next list refresh would drop this one. The shell
        /// remembers it until the server lists it.
        @discardableResult
        func showStartedChat(_ chat: StartedChat, serverName: String) -> String {
            let id = chat.storedSessionID
            startedChats.note(id)
            show(SessionListItem(id: id, title: "New chat", time: "Now", isPinned: false, serverName: serverName))
            return id
        }

        /// The started chats the server's list does not show yet. `syncSessions` puts them back after it replaces
        /// the list. A chat the server lists now is the server's from here on.
        func startedChatsToKeep(listed: Set<String>) -> [ChatSessionSummary] {
            let kept = startedChats.kept(among: sessions.map(\.id), listed: listed)
            return sessions.filter { kept.contains($0.id) }
        }
    }
#endif
