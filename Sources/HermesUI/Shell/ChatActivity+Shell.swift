#if canImport(UIKit)
    import HermesKit

    extension ShellModel {
        /// What chat `id` is doing, from its real model: a server chat's transcript and approvals, or a local chat's
        /// snapshot. Nil when no model is open for it (nothing runs there) or for DEBUG sample chats. It never makes a
        /// model, so watching every chat costs nothing.
        public func chatActivity(of id: String) -> ChatActivity? {
            if let live = liveChats?.existingChat(for: id) {
                let approval = live.approvals.first.map { ChatActivity.Approval(id: $0.id, command: $0.command) }
                return ChatActivity(transcript: live.state, approval: approval)
            }
            if let local = existingLocalChat(for: id) {
                return ChatActivity(local: local.snapshot)
            }
            return nil
        }

        /// The saved server a server chat belongs to (its model's own server), or nil for a local chat, a chat with no
        /// model open, or a DEBUG sample chat. Notifications key on it, so the same chat id on two servers never mixes.
        public func chatServer(of id: String) -> String? {
            liveChats?.existingChat(for: id)?.serverID?.uuidString
        }
    }
#endif
