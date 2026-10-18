#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// How a queued message ended. A message that was not sent is kept as a draft, so nothing the user said is lost.
    public enum OutboundOutcome: Equatable, Sendable {
        /// The chat takes the message to send.
        case sent
        /// The message is in a chat's composer as a draft. It was not sent.
        case keptAsDraft
    }

    /// Delivers messages that start outside a chat screen: Siri and Shortcuts, Quick Entry and the Share extension.
    ///
    /// A message names its chat loosely ("the chat I used last", "a new chat"), and the app may have just launched with
    /// no chat list and no connection. So delivery is a loop: every quarter second each waiting message is looked at
    /// again and moved along by ``OutboundPlanner``. It is sent when its chat can take it. When that never happens it
    /// lands in the chat's composer as a draft, so nothing the user said is lost.
    ///
    /// The coordinator never connects a chat itself. Opening a chat shows its screen, and the screen connects.
    ///
    /// A message for a new chat goes to a chat made on the saved server (`session.create`), so Hermes answers it. The
    /// message waits while the chat is made. When the server will not make one, the message is kept as a draft in a
    /// new local chat. Without a saved server, a new chat is a local placeholder, as before.
    @MainActor
    public final class OutboundCoordinator {
        private let model: ShellModel
        private let lastUsedID: @MainActor () -> String?
        private let chatStarter: ServerChatStarter?
        private let clock: @MainActor () -> Date
        private var waiting: [OutboundMessage] = []
        private var completions: [String: @MainActor (OutboundOutcome) -> Void] = [:]
        private var boundChats: [String: String] = [:]
        private var opened: Set<String> = []
        /// Messages whose server chat is being made, and messages whose chat could not be made.
        private var starting: Set<String> = []
        private var failedStarts: Set<String> = []
        private var loop: Task<Void, Never>?

        /// - Parameters:
        ///   - lastUsedID: the chat the user used last, if any.
        ///   - chatStarter: makes chats on the saved server. Without one, a new chat is a local placeholder.
        ///   - clock: the current time; tests and previews can supply their own.
        public init(
            model: ShellModel, lastUsedID: @escaping @MainActor () -> String?, chatStarter: ServerChatStarter? = nil,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.model = model
            self.lastUsedID = lastUsedID
            self.chatStarter = chatStarter
            self.clock = clock
        }

        /// How many messages have not been delivered yet.
        public var waitingCount: Int { waiting.count }

        /// Makes a chat on the saved server and opens it. Returns the chat's id.
        ///
        /// - Parameter profile: the bot to make the chat under. Nil uses the profile chosen in the app.
        @discardableResult
        public func startServerChat(profile: String? = nil) async throws(NewChatFailure) -> String {
            guard let chatStarter else { throw .notReachable }
            let started = try await chatStarter.start(profile: profile)
            return model.showStartedChat(started, serverName: chatStarter.serverName)
        }

        /// Queues a message. `completion` runs once it has been sent or kept as a draft, never before, and says which.
        public func submit(_ message: OutboundMessage, completion: (@MainActor (OutboundOutcome) -> Void)? = nil) {
            guard !waiting.contains(where: { $0.id == message.id }) else { return }
            waiting.append(message)
            if let completion { completions[message.id] = completion }
            runLoop()
        }

        /// Puts a message that an earlier launch kept as a draft into a new chat's composer. It is never sent. Returns
        /// false when no chat was made for it, and the caller keeps the message.
        public func restoreDraft(_ message: OutboundMessage) -> Bool {
            model.newChat()
            guard let created = model.selectedSessionID else { return false }
            keepAsDraft(message, in: created)
            return true
        }

        private func runLoop() {
            guard loop == nil else { return }
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.deliverWaiting() else { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                self?.loop = nil
            }
        }

        /// Moves every waiting message along. Returns whether some are still waiting.
        private func deliverWaiting() -> Bool {
            let now = clock()
            var remaining: [OutboundMessage] = []
            for message in waiting {
                if let outcome = deliver(message, now: now) {
                    boundChats[message.id] = nil
                    opened.remove(message.id)
                    completions.removeValue(forKey: message.id)?(outcome)
                } else {
                    remaining.append(message)
                }
            }
            waiting = remaining
            return !waiting.isEmpty
        }

        /// Returns how the message ended, or nil while it still waits.
        private func deliver(_ message: OutboundMessage, now: Date) -> OutboundOutcome? {
            let resolution = OutboundPlanner.resolve(
                message, bound: boundChats[message.id], knownChatIDs: Set(model.sessions.map(\.id)),
                lastUsedID: lastUsedID(), now: now)
            let chatID: String
            switch resolution {
            case .wait:
                return nil
            case .createChat:
                switch NewChatPolicy.kind(hasServer: chatStarter?.hasServer ?? false) {
                case .placeholder:
                    // `newChat()` opens and selects the chat it makes.
                    model.newChat()
                    // Nothing was placed, so the share is kept rather than sent.
                    guard let created = model.selectedSessionID else { return .keptAsDraft }
                    boundChats[message.id] = created
                    opened.insert(message.id)
                    chatID = created
                case .server:
                    // The chat is made in the background. A later pass finds it, or finds that it could not be made.
                    if failedStarts.remove(message.id) != nil { return keepInLocalChat(message) }
                    startChat(for: message)
                    return nil
                }
            case .chat(let id):
                chatID = id
            }
            // Showing the chat starts its connection, so open it once and then wait.
            if opened.insert(message.id).inserted { model.open(chatID) }
            return place(message, in: chatID, now: now)
        }

        /// Makes the server chat for a message, once. The loop picks the chat up when it is there.
        private func startChat(for message: OutboundMessage) {
            guard starting.insert(message.id).inserted else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let id = try await self.startServerChat(profile: message.profile)
                    self.bind(message.id, toStartedChat: id)
                } catch {
                    self.failedStarts.insert(message.id)
                }
                self.starting.remove(message.id)
            }
        }

        private func bind(_ messageID: String, toStartedChat id: String) {
            guard let index = waiting.firstIndex(where: { $0.id == messageID }) else { return }
            boundChats[messageID] = id
            // Showing the chat opened it. It gets its own time to connect: making it does not count against it.
            opened.insert(messageID)
            waiting[index].createdAt = clock()
        }

        /// The server would not make a chat. The message waits as a draft in a new local chat, so nothing is lost. It
        /// is not sent, because a local chat can only be answered by the demo.
        private func keepInLocalChat(_ message: OutboundMessage) -> OutboundOutcome {
            model.newChat()
            guard let created = model.selectedSessionID else { return .keptAsDraft }
            keepAsDraft(message, in: created)
            return .keptAsDraft
        }

        private func place(_ message: OutboundMessage, in id: String, now: Date) -> OutboundOutcome? {
            let live = model.liveChat(for: id)
            let step = OutboundPlanner.step(
                for: message, isLive: model.serverSessionIDs.contains(id), readiness: Self.readiness(of: live), now: now
            )
            switch step {
            case .wait:
                return nil
            case .send:
                send(message, in: id, live: live)
                return .sent
            case .saveAsDraft:
                keepAsDraft(message, in: id)
                return .keptAsDraft
            }
        }

        /// A server chat with no live model yet is still loading; it has not failed.
        private static func readiness(of chat: LiveChatModel?) -> ChatReadiness {
            guard let chat else { return .loading }
            switch chat.phase {
            case .ready: return .ready
            case .loading: return .loading
            case .failed: return .failed
            }
        }

        private func send(_ message: OutboundMessage, in id: String, live: LiveChatModel?) {
            if let live {
                live.send(message.text, attachments: message.attachments)
                return
            }
            // A placeholder chat sends its draft. Lend it the text, then give the user's own draft back.
            let own = model.drafts[id, default: ""]
            model.drafts[id] = message.text
            model.send(in: id)
            model.drafts[id] = own
            // Placeholder chats cannot send files yet. They wait in the chat's attachment tray.
            keepAttachments(message, in: id)
        }

        private func keepAsDraft(_ message: OutboundMessage, in id: String) {
            model.drafts[id] = OutboundPlanner.draft(existing: model.drafts[id, default: ""], adding: message.text)
            keepAttachments(message, in: id)
        }

        private func keepAttachments(_ message: OutboundMessage, in id: String) {
            guard !message.attachments.isEmpty else { return }
            model.attachments[id, default: []].append(contentsOf: message.attachments)
        }
    }
#endif
