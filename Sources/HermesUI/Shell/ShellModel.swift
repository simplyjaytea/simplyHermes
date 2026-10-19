#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI

    /// A chat session as the shell lists it. Real sessions come from WP-40; the shell only needs these fields.
    public struct ChatSessionSummary: Identifiable, Hashable, Sendable {
        public let id: String
        public var title: String
        public var subtitle: String
        public var serverName: String

        public init(id: String, title: String, subtitle: String, serverName: String) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.serverName = serverName
        }
    }

    /// An approval a chat waits on, as the alert banner (Q49) and the row badges show it.
    public struct ApprovalAlert: Identifiable, Hashable, Sendable {
        public let id: String
        public let sessionID: String
        public let sessionTitle: String
        public let command: String
    }

    /// A transcript line for the shell's placeholder chat. WP-30 replaces it with the real transcript.
    public struct ShellMessage: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case user
            case assistant
            case tool(command: String)
            case approval
        }

        public let id: String
        public let kind: Kind
        public var text: String

        public init(id: String, kind: Kind, text: String) {
            self.id = id
            self.kind = kind
            self.text = text
        }
    }

    /// Shell state that must survive fold, unfold and layout changes: section, selected chat,
    /// open chats (tabs), recently closed chats, per-chat drafts and scroll positions.
    @MainActor
    @Observable
    public final class ShellModel {
        public var selectedSection: AppSection = .chats
        public var sessions: [ChatSessionSummary]
        public var selectedSessionID: String?
        /// Chats open as tabs, in the order they were opened.
        public private(set) var openSessionIDs: [String] = []
        /// Closed chats, most recent last, for "Reopen closed chat".
        public private(set) var closedSessionIDs: [String] = []
        public var drafts: [String: String] = [:]
        /// Files attached in each chat's composer. They go out with the next message of that chat.
        public var attachments: [String: [ComposerAttachment]] = [:]
        public var scrollAnchors: [String: String] = [:]
        public var transcripts: [String: [ShellMessage]] = [:]
        /// Chats with a turn streaming right now.
        public private(set) var streamingSessionIDs: Set<String> = []
        @ObservationIgnored private var streamTasks: [String: Task<Void, Never>] = [:]
        /// Chats read from the connected server (WP-30). Nil when there is no server connection to read from.
        @ObservationIgnored public var liveChats: LiveChatStore?
        /// Browses the active server's files for the preview rail (WP-37). Nil when there is no server connection.
        @ObservationIgnored public var workspaceBrowser: WorkspaceBrowserModel?
        /// Ids of the chats the server listed. These open as live chats; the rest stay placeholders.
        public private(set) var serverSessionIDs: Set<String> = []
        public var isPalettePresented = false
        /// Report a bug, opened from the command palette.
        public var isBugReportPresented = false
        /// Set by the palette's Report a bug command; the report opens when the palette finishes closing.
        public var opensBugReportAfterPalette = false
        /// PNG of the screen the user shook to open Report a bug. Nil when opened another way.
        public var bugReportScreenshot: Data?
        public var showsPreviewRail = true
        /// Forces a layout, for UI tests and the debug menu. `nil` follows the screen and posture.
        public var layoutOverride: DisplayLayout?
        /// A session link to open, set by the URL handler. The shell opens it, then clears this (WP-40).
        public var pendingSessionReference: SessionReference?
        /// A calm message the shell shows when a session link cannot be opened.
        public var sessionNotice: String?

        public init(sessions: [ChatSessionSummary] = ShellModel.sampleSessions, selectedSessionID: String? = nil) {
            self.sessions = sessions
            let initial = selectedSessionID ?? sessions.first?.id
            self.selectedSessionID = initial
            for session in sessions {
                transcripts[session.id] = ShellModel.sampleTranscript(for: session)
            }
            if let initial {
                openSessionIDs = [initial]
            }
        }

        public var selectedSession: ChatSessionSummary? {
            sessions.first { $0.id == selectedSessionID }
        }

        public func session(id: String) -> ChatSessionSummary? {
            sessions.first { $0.id == id }
        }

        /// Shows a chat and adds it to the open tabs.
        public func open(_ id: String) {
            selectedSection = .chats
            selectedSessionID = id
            if !openSessionIDs.contains(id) {
                openSessionIDs.append(id)
            }
            closedSessionIDs.removeAll { $0 == id }
        }

        /// Closes a chat tab. Its draft stays, so reopening restores it.
        public func close(_ id: String) {
            openSessionIDs.removeAll { $0 == id }
            closedSessionIDs.removeAll { $0 == id }
            closedSessionIDs.append(id)
            if selectedSessionID == id {
                selectedSessionID = openSessionIDs.last
            }
        }

        public func closeSelected() {
            if let selectedSessionID {
                close(selectedSessionID)
            }
        }

        public var canReopenClosed: Bool { !closedSessionIDs.isEmpty }

        public func reopenLastClosed() {
            if let last = closedSessionIDs.popLast() {
                open(last)
            }
        }

        /// Replaces the listed chats with the server's (WP-40). Chats started here stay. Their transcripts arrive with
        /// WP-30, so a synced chat opens empty for now.
        public func syncSessions(_ items: [SessionListItem]) {
            let local = sessions.filter { $0.id.hasPrefix("new-") }
            let synced = items.map {
                ChatSessionSummary(id: $0.id, title: $0.title, subtitle: $0.time ?? "", serverName: $0.serverName)
            }
            sessions = local + synced
            serverSessionIDs = Set(items.map(\.id))
            for session in sessions where transcripts[session.id] == nil { transcripts[session.id] = [] }
            let ids = Set(sessions.map(\.id))
            openSessionIDs.removeAll { !ids.contains($0) }
            if let selected = selectedSessionID, !ids.contains(selected) { selectedSessionID = openSessionIDs.last }
        }

        /// Opens a listed chat, adding it first when the list does not hold it yet (a search result).
        public func show(_ item: SessionListItem) {
            if session(id: item.id) == nil {
                sessions.append(
                    ChatSessionSummary(
                        id: item.id, title: item.title, subtitle: item.time ?? "", serverName: item.serverName))
                transcripts[item.id] = []
            }
            serverSessionIDs.insert(item.id)
            open(item.id)
        }

        /// Starts a new local chat. WP-40 replaces this with a server-side session.
        public func newChat() {
            let id = "new-\(sessions.count + 1)"
            sessions.insert(
                ChatSessionSummary(id: id, title: "New chat", subtitle: "Now", serverName: "home-server"), at: 0)
            transcripts[id] = []
            open(id)
        }

        /// The live chat for a listed server session, or nil for a placeholder chat.
        func liveChat(for id: String) -> LiveChatModel? {
            guard serverSessionIDs.contains(id) else { return nil }
            return liveChats?.chat(for: id)
        }

        public func draftBinding(for id: String) -> Binding<String> {
            Binding(
                get: { self.drafts[id, default: ""] },
                set: { self.drafts[id] = $0 }
            )
        }

        public func attachmentsBinding(for id: String) -> Binding<[ComposerAttachment]> {
            Binding(
                get: { self.attachments[id, default: []] },
                set: { self.attachments[id] = $0 }
            )
        }

        public func isStreaming(_ id: String) -> Bool {
            streamingSessionIDs.contains(id)
        }

        /// Sends the draft as a user message. The demo reply streams in word by word.
        public func send(in id: String) {
            let text = drafts[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            drafts[id] = ""
            append(ShellMessage(id: UUID().uuidString, kind: .user, text: text), to: id)
            startDemoStream(in: id)
        }

        /// Streams a canned reply into a chat, a few words at a time, so fold changes can be tested mid-stream.
        public func startDemoStream(in id: String, words: Int = 60) {
            guard !streamingSessionIDs.contains(id) else { return }
            streamingSessionIDs.insert(id)
            let messageID = UUID().uuidString
            append(ShellMessage(id: messageID, kind: .assistant, text: ""), to: id)
            streamTasks[id] = Task { [weak self] in
                for index in 0..<words {
                    try? await Task.sleep(for: .milliseconds(120))
                    if Task.isCancelled { break }
                    self?.appendWord("word\(index)", to: messageID, in: id)
                }
                self?.streamingSessionIDs.remove(id)
                self?.streamTasks[id] = nil
            }
        }

        /// Stops the running turn in a chat.
        public func stop(in id: String) {
            streamTasks[id]?.cancel()
            streamTasks[id] = nil
            streamingSessionIDs.remove(id)
        }

        /// The approval the chat is waiting on, if any.
        public func pendingApproval(in id: String) -> ShellMessage? {
            transcripts[id]?.last { $0.kind == .approval }
        }

        /// Whether a chat waits on an approval. Drives the badge on its sidebar row and tab.
        public func needsApproval(_ id: String) -> Bool {
            firstApproval(in: id) != nil
        }

        /// Approvals waiting in chats the user is not looking at, in sidebar order. Drives the alert banner (Q49).
        public var approvalAlerts: [ApprovalAlert] {
            let watching = selectedSection == .chats ? selectedSessionID : nil
            return sessions.compactMap { $0.id == watching ? nil : firstApproval(in: $0.id) }
        }

        /// Answers an approval from an alert. A live chat answers on the server, a placeholder chat locally.
        public func answer(_ alert: ApprovalAlert, approved: Bool) {
            let chat = liveChats?.existingChat(for: alert.sessionID)
            if let approval = chat?.approvals.first(where: { $0.id == alert.id }) {
                chat?.answer(approval, approved ? .once : .deny)
            } else {
                resolveApproval(in: alert.sessionID, approved: approved)
            }
        }

        /// The first approval a chat waits on: a live chat's, else a placeholder transcript's.
        private func firstApproval(in id: String) -> ApprovalAlert? {
            guard let summary = session(id: id) else { return nil }
            if let approval = liveChats?.existingChat(for: id)?.approvals.first {
                return ApprovalAlert(
                    id: approval.id, sessionID: id, sessionTitle: summary.title, command: approval.command)
            }
            guard let approval = pendingApproval(in: id) else { return nil }
            return ApprovalAlert(id: approval.id, sessionID: id, sessionTitle: summary.title, command: approval.text)
        }

        /// Answers the pending approval. WP-31 sends the answer to the server.
        public func resolveApproval(in id: String, approved: Bool) {
            guard let approval = pendingApproval(in: id) else { return }
            transcripts[id]?.removeAll { $0.id == approval.id }
            let note = approved ? "Approved: \(approval.text)" : "Denied: \(approval.text)"
            append(ShellMessage(id: UUID().uuidString, kind: .assistant, text: note), to: id)
            if approved {
                startDemoStream(in: id, words: 20)
            }
        }

        private func append(_ message: ShellMessage, to id: String) {
            transcripts[id, default: []].append(message)
        }

        private func appendWord(_ word: String, to messageID: String, in id: String) {
            guard let index = transcripts[id]?.firstIndex(where: { $0.id == messageID }) else { return }
            let current = transcripts[id]?[index].text ?? ""
            transcripts[id]?[index].text = current.isEmpty ? word : current + " " + word
        }
    }
#endif
