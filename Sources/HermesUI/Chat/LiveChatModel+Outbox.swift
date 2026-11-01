#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// The outgoing messages of a chat (WP-3, WP-4): saving a typed message, sending the waiting ones, and retrying or
    /// dropping one that failed. Kept apart from ``LiveChatModel`` so that class stays readable.
    extension LiveChatModel {
        /// Sends what the composer holds (WP-3). Typed text is saved to the outbox first, and goes out once the chat can
        /// take it, even if the app stops in between. Returns true once the text is saved or handed on, so the composer may
        /// clear. False leaves the draft where it is.
        @discardableResult
        public func send(_ text: String, attachments: [ComposerAttachment] = []) async -> Bool {
            // Plan Q44: while the server is out of reach, text goes to the on-device model. Files need Hermes.
            if attachments.isEmpty, offline.send(text) { return true }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Files and slash commands run on the controller at once. They are not saved to the outbox yet.
            if !attachments.isEmpty || SlashCommand(trimmed) != nil {
                guard let controller else { return false }
                HermesSounds.play(.send)
                if let composerText = await controller.send(text, attachments: attachments) {
                    prefill = composerText
                    return false
                }
                return true
            }
            guard !trimmed.isEmpty else { return false }
            // Without durable storage a message would be lost on relaunch, so it is not sent, and the text stays (M6).
            guard OutboxServices.isDurable else {
                outboxError = String(localized: "Messages can't be saved on this device, so nothing was sent.")
                return false
            }
            // A live chat always belongs to the active server. Without one the text is still kept, under no server.
            let connectionID = connections.active?.id.uuidString ?? ""
            do {
                try await outbox.insert(
                    OutboundRecord(
                        connectionID: connectionID, chatID: storedSessionID, text: trimmed, createdAt: Date()))
            } catch {
                outboxError = Self.saveFailureMessage
                return false
            }
            outboxError = nil
            HermesSounds.play(.send)
            await refreshOutbox()
            drainTask = Task { await drainOutbox() }
            return true
        }

        /// Starts a composer send. False while an earlier composer send of this chat is still saving (review M5).
        public func beginComposerSend() -> Bool {
            composerSend.begin()
        }

        /// Ends the composer send that ``beginComposerSend()`` started.
        public func endComposerSend() {
            composerSend.end()
        }

        /// Sends the chat's waiting messages if Hermes can take them, then refreshes the rows the screen shows.
        func drainOutbox() async {
            guard let drainer else { return }
            do {
                try await drainer.drain()
            } catch {
                outboxError = Self.outboxMessage(for: error)
            }
            await refreshOutbox()
        }

        /// Sends a failed message again (WP-4). Detached, it waits for the next attach.
        public func retryOutbox(_ id: UUID) {
            Task {
                do {
                    if let drainer {
                        try await drainer.retry(id)
                    } else {
                        try await outbox.updateState(.pending, forID: id, ifCurrently: .failed)
                    }
                } catch {
                    outboxError = Self.outboxMessage(for: error)
                }
                await refreshOutbox()
            }
        }

        /// Drops a failed message the user no longer wants (WP-4). A message that is being sent cannot be dropped.
        public func deleteOutbox(_ id: UUID) {
            Task {
                do {
                    try await outbox.remove(id: id, ifCurrently: .failed)
                } catch {
                    outboxError = Self.outboxMessage(for: error)
                }
                await refreshOutbox()
            }
        }

        /// Starts a drain when there are waiting messages and the chat is free to send them.
        func drainSoon() {
            guard !outboxRows.isEmpty else { return }
            drainTask = Task { await drainOutbox() }
        }

        func refreshOutbox() async {
            do {
                outboxRows = try await outbox.records(inChat: storedSessionID).filter { !$0.state.isSent }
            } catch {
                outboxError = Self.outboxMessage(for: error)
            }
        }

        /// A message could not be saved, so it was not sent. Where the text went is up to the path that failed.
        static let saveFailureMessage = String(localized: "Couldn't save your message, so nothing was sent.")

        /// The saved messages could not be read or updated. They are still in the outbox.
        static func outboxMessage(for error: any Error) -> String {
            String(localized: "Couldn't update your waiting messages. They are still saved.")
        }
    }
#endif
