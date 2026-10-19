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
        /// Bot Chats opened from the Bots screen (WP-42). They are hidden, so the sessions list never lists them.
        public private(set) var botChatIDs: Set<String> = []
        /// Chats made on the server from outside the chat list, which the server does not list yet.
        @ObservationIgnored var startedChats = StartedChats()
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
            let started = startedChatsToKeep(listed: Set(items.map(\.id)))
            let local = sessions.filter { $0.id.hasPrefix("new-") || botChatIDs.contains($0.id) }
            let synced = items.map {
                ChatSessionSummary(id: $0.id, title: $0.title, subtitle: $0.time ?? "", serverName: $0.serverName)
            }
            sessions = local + synced
            serverSessionIDs = Set(items.map(\.id)).union(botChatIDs)
            sessions.insert(contentsOf: started, at: local.count)
            serverSessionIDs.formUnion(started.map(\.id))
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

        /// Opens a bot's Bot Chat from the Bots screen (WP-42). The chat is hidden, so it is kept across list syncs.
        public func openBotChat(_ item: SessionListItem) {
            botChatIDs.insert(item.id)
            show(item)
        }

        /// Forgets the Bot Chats and the new chats of the server that was active. A server switch calls this.
        /// A profile change does not, because opening a bot switches the profile (WP-42).
        public func forgetServerChats() {
            botChatIDs = []
            startedChats = StartedChats()
        }

        /// Creates the server chat for a New chat's first message. Nil when no server is saved: New chats then stay
        /// placeholders.
        @ObservationIgnored public var startServerChat: (@MainActor () async throws -> SessionListItem?)?
        /// Hands a New chat's first message and its files to the chat's live model, which sends them on attach.
        @ObservationIgnored public var handOffFirstMessage: (@MainActor (String, String, [ComposerAttachment]) -> Void)?
        /// New chats whose server chat is created by their first message. Until then they are placeholders.
        @ObservationIgnored private var unstartedChatIDs: Set<String> = []
        /// The first message being sent in each New chat. A repeat send there joins it, so a double tap sends once.
        @ObservationIgnored private var startingChats: [String: Task<Void, Never>] = [:]
        /// Counts placeholder ids, so a new placeholder never reuses the id of one still open.
        @ObservationIgnored private var placeholderCount = 0
        /// Why the last first message failed, in words. The shell shows it in an alert, which clears it.
        public var newChatError: String?

        /// Starts a chat. With a server saved it is a placeholder until its first message creates the server chat, so
        /// New chat never waits on the network. An empty chat not yet started is shown again, so repeat taps make one.
        public func newChat() {
            if let empty = sessions.first(where: { session in
                unstartedChatIDs.contains(session.id) && drafts[session.id, default: ""].isEmpty
                    && attachments[session.id, default: []].isEmpty && transcripts[session.id, default: []].isEmpty
            }) {
                open(empty.id)
                return
            }
            let id = addPlaceholderChat()
            if startServerChat != nil { unstartedChatIDs.insert(id) }
        }

        /// Creates the server chat for a first message and sends the message there. A send in the same chat while that
        /// runs joins it. A failure keeps the text and the files in the composer and sets ``newChatError``.
        private func startFirstMessage(in id: String) -> Task<Void, Never>? {
            if let running = startingChats[id] { return running }
            guard let startServerChat else { return nil }
            let typed = drafts[id, default: ""]
            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !attachments[id, default: []].isEmpty else { return nil }
            newChatError = nil
            let task: Task<Void, Never> = Task {
                defer { self.startingChats[id] = nil }
                do {
                    guard let item = try await startServerChat() else {
                        self.newChatError = Self.newChatMessage(for: nil)
                        return
                    }
                    self.adopt(item, replacing: id)
                    let files = self.attachments.removeValue(forKey: item.id) ?? []
                    self.handOffFirstMessage?(item.id, text, files)
                    if self.drafts[item.id] == typed { self.drafts[item.id] = nil }
                } catch {
                    self.newChatError = Self.newChatMessage(for: error)
                }
            }
            startingChats[id] = task
            return task
        }

        /// Gives a New chat its server id. The sidebar row, tab, transcript, draft and files move to the server chat.
        private func adopt(_ item: SessionListItem, replacing placeholderID: String) {
            unstartedChatIDs.remove(placeholderID)
            startedChats.note(item.id)
            serverSessionIDs.insert(item.id)
            let summary = ChatSessionSummary(
                id: item.id, title: item.title, subtitle: item.time ?? "", serverName: item.serverName)
            if let index = sessions.firstIndex(where: { $0.id == placeholderID }) {
                sessions[index] = summary
            } else {
                sessions.insert(summary, at: 0)
            }
            transcripts[item.id] = transcripts.removeValue(forKey: placeholderID) ?? []
            drafts[item.id] = drafts.removeValue(forKey: placeholderID)
            attachments[item.id] = attachments.removeValue(forKey: placeholderID)
            scrollAnchors[item.id] = scrollAnchors.removeValue(forKey: placeholderID)
            openSessionIDs = openSessionIDs.map { $0 == placeholderID ? item.id : $0 }
            closedSessionIDs = closedSessionIDs.map { $0 == placeholderID ? item.id : $0 }
            if selectedSessionID == placeholderID { selectedSessionID = item.id }
        }

        /// The words the user reads when a first message does not start its chat. A nil error means no chat came back.
        static func newChatMessage(for error: Error?) -> String {
            if let offline = error as? ServerNotConnectedError {
                return offline.isConnecting
                    ? "\(offline.serverName) is still connecting. Try again in a moment."
                    : "\(offline.serverName) is not connected. Connect to it, then try again."
            }
            return "Could not start a new chat. Try again."
        }

        /// Adds an empty chat at the top of the list and opens it. Ids count up: a count of chats can repeat after a
        /// list sync and reuse an id that is still open.
        private func addPlaceholderChat() -> String {
            placeholderCount += 1
            let id = "new-\(placeholderCount)"
            sessions.insert(
                ChatSessionSummary(id: id, title: "New chat", subtitle: "Now", serverName: "home-server"), at: 0)
            transcripts[id] = []
            open(id)
            return id
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

        /// Sends the draft as a user message. The demo reply streams in word by word. A New chat's first message
        /// creates its server chat instead, and the returned task ends once that message is sent or has failed.
        @discardableResult
        public func send(in id: String) -> Task<Void, Never>? {
            if unstartedChatIDs.contains(id) { return startFirstMessage(in: id) }
            let text = drafts[id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            drafts[id] = ""
            append(ShellMessage(id: UUID().uuidString, kind: .user, text: text), to: id)
            startDemoStream(in: id)
            return nil
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
