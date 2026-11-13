#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The outgoing messages of a chat (WP-3, WP-4): saving a typed message, sending the waiting ones, and retrying or
    /// dropping one that failed. Kept apart from ``LiveChatModel`` so that class stays readable.
    extension LiveChatModel {
        /// Watches the chat's pill for the rest of its life. A move back into `.connected` sends the waiting messages,
        /// whether or not the chat is on screen (WP-8; a message must not wait until the next send).
        func watchPill() {
            withObservationTracking {
                _ = status.pill
            } onChange: { [weak self] in
                Task { @MainActor in self?.pillChanged() }
            }
        }

        func pillChanged() {
            // A retired chat belongs to a server that is no longer active, and it does not watch again, so it can be
            // freed (row 108). The decision is OutboxResume.reaction.
            guard !isRetired else { return }
            let now = status.pill
            let previous = lastPill
            lastPill = now
            let reaction = OutboxResume.reaction(
                from: previous, to: now, isRetired: isRetired, isAttached: controller != nil,
                isOnAnotherServer: isOnAnotherServer)
            switch reaction {
            case .nothing:
                break
            case .attach:
                // Detached (the chat is not open): attaching connects it, and attaching sends the waiting messages.
                Task { await attach() }
            case .drain:
                // Not `drainSoon()`: another screen may have changed the outbox since this chat last refreshed it, and
                // the drain reads the records itself.
                drainTask = Task { await drainOutbox() }
            }
            watchPill()
        }

        /// Sends what the composer holds (WP-3). Typed text is saved to the outbox first, and goes out once the chat can
        /// take it, even if the app stops in between. Returns true once the text is saved or handed on, so the composer may
        /// clear. False leaves the draft where it is.
        @discardableResult
        public func send(_ text: String, attachments: [ComposerAttachment] = []) async -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Files and slash commands are not saved to the outbox, so they go out only when the chat can take them now.
            // Otherwise the composer keeps them, and the user is told why (Moss, 54b698d).
            if !attachments.isEmpty || SlashCommand(trimmed) != nil {
                guard let controller else {
                    outboxError = Self.notNowMessage
                    return false
                }
                switch await controller.send(text, attachments: attachments) {
                case .sent:
                    outboxError = nil
                    HermesSounds.play(.send)
                    return true
                case .prefill(let composerText):
                    prefill = composerText
                    return false
                case .notSent:
                    outboxError = Self.notNowMessage
                    return false
                case .failed(let reason):
                    // The failed row shows the attempt. The composer keeps the text and files to send again (Moss, be2cee0).
                    outboxError = String(localized: "Not sent: \(reason)")
                    return false
                }
            }
            guard !trimmed.isEmpty else { return false }
            // Without durable storage a message would be lost on relaunch, so it is not sent, and the text stays (M6).
            guard OutboxServices.isDurable else {
                outboxError = String(localized: "Messages can't be saved on this device, so nothing was sent.")
                return false
            }
            // The chat's own server, the same key its drainer sends under. Without one the text is still kept.
            do {
                try await outbox.insert(
                    OutboundRecord(
                        connectionID: outboxConnectionID, chatID: storedSessionID, text: trimmed, createdAt: Date()))
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
            guard controller != nil, let drainer else { return }
            // WP-8: while the chat cannot reach its server, its waiting messages stay where they are. Nothing is submitted
            // over a socket the status says is down, and the drain runs again when the chat recovers.
            guard status.pill != .unreachable else {
                await refreshOutbox()
                return
            }
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
                    if controller != nil, let drainer {
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
                outboxRows = try await outbox.records(inChat: storedSessionID).filter {
                    !$0.state.isSent && $0.connectionID == outboxConnectionID
                }
            } catch {
                outboxError = Self.outboxMessage(for: error)
            }
        }

        /// A message could not be saved, so it was not sent. Where the text went is up to the path that failed.
        static let saveFailureMessage = String(localized: "Couldn't save your message, so nothing was sent.")

        /// Files and commands cannot wait to be sent, so they stay in the composer until Hermes is ready.
        static let notNowMessage = String(
            localized: "Files and commands go out only when Hermes is ready. Nothing was sent. Try again soon.")

        /// The saved messages could not be read or updated. They are still in the outbox.
        static func outboxMessage(for error: any Error) -> String {
            String(localized: "Couldn't update your waiting messages. They are still saved.")
        }
    }
#endif
