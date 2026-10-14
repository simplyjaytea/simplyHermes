#if canImport(UIKit)
    import Foundation

    /// Placeholder chats until WP-40 lists real sessions and WP-30 renders real transcripts.
    extension ShellModel {
        public static let sampleSessions: [ChatSessionSummary] = [
            ChatSessionSummary(
                id: "backup", title: "Backup cron fix", subtitle: "Approval needed", serverName: "home-server"),
            ChatSessionSummary(id: "blog", title: "Blog post draft", subtitle: "Yesterday", serverName: "home-server"),
            ChatSessionSummary(id: "router", title: "Router firmware", subtitle: "Monday", serverName: "office-mac"),
        ]

        static func sampleTranscript(for session: ChatSessionSummary) -> [ShellMessage] {
            var messages: [ShellMessage] = []
            for index in 1...24 {
                messages.append(
                    ShellMessage(
                        id: "\(session.id)-q\(index)",
                        kind: .user,
                        text: "Question \(index) about \(session.title.lowercased())"
                    )
                )
                messages.append(
                    ShellMessage(
                        id: "\(session.id)-a\(index)",
                        kind: .assistant,
                        text: "Answer \(index). Checked the logs and the config; everything else looks fine."
                    )
                )
            }
            guard session.id == "backup" else { return messages }
            messages.append(ShellMessage(id: "backup-ask", kind: .user, text: "Why did last night's backup cron fail?"))
            messages.append(
                ShellMessage(
                    id: "backup-tool",
                    kind: .tool(command: "grep backup /var/log/syslog"),
                    text: "rsync: connection unexpectedly closed (code 255)"
                )
            )
            messages.append(
                ShellMessage(
                    id: "backup-why",
                    kind: .assistant,
                    text: "The NAS rejected the SSH key after its update. I can re-add the key and rerun the job."
                )
            )
            messages.append(ShellMessage(id: "backup-approval", kind: .approval, text: "ssh-copy-id backup@nas.local"))
            return messages
        }
    }
#endif
