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
    }
#endif
