#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Delivers messages that start outside a chat screen: Siri and Shortcuts, Quick Entry and the Share extension.
    ///
    /// A message names its chat loosely ("the chat I used last", "a new chat"), and the app may have just launched with
    /// no chat list and no connection. So delivery is a loop: every quarter second each waiting message is looked at
    /// again and moved along by ``OutboundPlanner``. It is sent when its chat can take it. When that never happens it
    /// lands in the chat's composer as a draft, so nothing the user said is lost.
    ///
    /// The coordinator never connects a chat itself. Opening a chat shows its screen, and the screen connects.
    @MainActor
    public final class OutboundCoordinator {
        private let model: ShellModel
        private let lastUsedID: @MainActor () -> String?
        private let clock: @MainActor () -> Date
        private var waiting: [OutboundMessage] = []
        private var completions: [String: @MainActor () -> Void] = [:]
        private var boundChats: [String: String] = [:]
        private var opened: Set<String> = []
        private var loop: Task<Void, Never>?

        /// - Parameters:
        ///   - lastUsedID: the chat the user used last, if any.
        ///   - clock: the current time; tests and previews can supply their own.
        public init(
            model: ShellModel, lastUsedID: @escaping @MainActor () -> String?,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.model = model
            self.lastUsedID = lastUsedID
            self.clock = clock
        }

        /// How many messages have not been delivered yet.
        public var waitingCount: Int { waiting.count }

        /// Queues a message. `completion` runs once it has been sent or saved as a draft, never before.
        public func submit(_ message: OutboundMessage, completion: (@MainActor () -> Void)? = nil) {
            guard !waiting.contains(where: { $0.id == message.id }) else { return }
            waiting.append(message)
            if let completion { completions[message.id] = completion }
            runLoop()
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
                if deliver(message, now: now) {
                    boundChats[message.id] = nil
                    opened.remove(message.id)
                    completions.removeValue(forKey: message.id)?()
                } else {
                    remaining.append(message)
                }
            }
            waiting = remaining
            return !waiting.isEmpty
        }

        /// Returns true once the message is done: sent, or kept as a draft.
        private func deliver(_ message: OutboundMessage, now: Date) -> Bool {
            let resolution = OutboundPlanner.resolve(
                message, bound: boundChats[message.id], knownChatIDs: Set(model.sessions.map(\.id)),
                lastUsedID: lastUsedID(), now: now)
            let chatID: String
            switch resolution {
            case .wait:
                return false
            case .createChat:
                // `newChat()` opens and selects the chat it makes.
                model.newChat()
                guard let created = model.selectedSessionID else { return true }
                boundChats[message.id] = created
                opened.insert(message.id)
                chatID = created
            case .chat(let id):
                chatID = id
            }
            // Showing the chat starts its connection, so open it once and then wait.
            if opened.insert(message.id).inserted { model.open(chatID) }
            return place(message, in: chatID, now: now)
        }

        private func place(_ message: OutboundMessage, in id: String, now: Date) -> Bool {
            let live = model.liveChat(for: id)
            let step = OutboundPlanner.step(
                for: message, isLive: model.serverSessionIDs.contains(id), readiness: Self.readiness(of: live), now: now
            )
            switch step {
            case .wait:
                return false
            case .send:
                send(message, in: id, live: live)
                return true
            case .saveAsDraft:
                keepAsDraft(message, in: id)
                return true
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
