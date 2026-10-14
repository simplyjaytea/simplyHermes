#if canImport(UIKit)
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
        public var scrollAnchors: [String: String] = [:]
        public var transcripts: [String: [ShellMessage]] = [:]
        /// Chats with a turn streaming right now.
        public private(set) var streamingSessionIDs: Set<String> = []
        @ObservationIgnored private var streamTasks: [String: Task<Void, Never>] = [:]
        public var isPalettePresented = false
        public var showsPreviewRail = true
        /// Forces a layout, for UI tests and the debug menu. `nil` follows the screen and posture.
        public var layoutOverride: DisplayLayout?

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

        /// Starts a new local chat. WP-40 replaces this with a server-side session.
        public func newChat() {
            let id = "new-\(sessions.count + 1)"
            sessions.insert(
                ChatSessionSummary(id: id, title: "New chat", subtitle: "Now", serverName: "home-server"), at: 0)
            transcripts[id] = []
            open(id)
        }

        public func draftBinding(for id: String) -> Binding<String> {
            Binding(
                get: { self.drafts[id, default: ""] },
                set: { self.drafts[id] = $0 }
            )
        }

        public func scrollAnchorBinding(for id: String) -> Binding<String?> {
            Binding(
                get: { self.scrollAnchors[id] },
                set: { self.scrollAnchors[id] = $0 }
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
