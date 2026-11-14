#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// How a chat attach is wired to the outbox, and what it builds on the way (board row 140). Kept apart from
    /// ``LiveChatModel`` so that class stays under the lint size limit.
    extension LiveChatModel {
        /// What an attach builds step by step, held until the last step commits it.
        final class PendingAttach {
            var client: GatewayClient?
            var controller: ChatSessionController?
            var states: AsyncStream<ChatSnapshot>?
            var approvals: AsyncStream<[PendingServerRequest]>?
            var drainer: OutboxDrainer?

            /// Ends the approvals stream of an attach that did not commit, so the broker drops its observer.
            func cancelApprovals() {
                guard let stream = approvals else { return }
                approvals = nil
                // A cancelled consumer terminates the stream, which removes the broker's observer.
                Task { for await _ in stream {} }.cancel()
            }
        }

        /// Gives the chat's drainer this attach's controller, and recovers messages that were mid-send at launch.
        func wireOutbox(_ built: PendingAttach) async {
            guard let controller = built.controller else { return }
            let refresh: @Sendable () async -> Void = { @MainActor [weak self] in await self?.refreshOutbox() }
            let (drainer, isNew) = drainers.drainer(forChat: storedSessionID, connection: outboxConnectionID) {
                OutboxDrainer(
                    store: outbox, chatID: storedSessionID, connectionID: outboxConnectionID, submitter: controller)
            }
            built.drainer = drainer
            await drainer.observe(owner: outboxObserver, refresh)
            do {
                if isNew {
                    // The chat's first attach this launch: messages that were mid-send when the app stopped go out
                    // again, once.
                    try await drainer.recoverInterrupted()
                } else {
                    // A reattach (Try again, a screen coming back, or this chat rebuilt after a server switch or in
                    // another window). A message may be in flight on the old controller, so nothing is recovered: the
                    // drainer finishes it there and sends the rest through this one.
                    previousSubmitter = await drainer.currentSubmitter
                    await drainer.use(controller)
                }
                _ = try await outbox.pruneSent(inChat: storedSessionID)
            } catch {
                outboxError = Self.outboxMessage(for: error)
            }
        }

        /// Undoes the controller step: detaches the controller and ends the approvals stream, so the shared broker does
        /// not keep one observer per failed attach.
        func unwireController(_ built: PendingAttach) async {
            built.cancelApprovals()
            await built.controller?.detach()
        }

        /// An abandoned attach puts back the submitter it replaced, unless another attach has replaced it since.
        func unwireOutbox(_ built: PendingAttach) async {
            if let controller = built.controller, let drainer = built.drainer, let previous = previousSubmitter {
                await drainer.replace(controller, with: previous)
            }
            previousSubmitter = nil
            // A retired chat never attaches again, so its observer goes too (``retire()`` only knows a committed drainer).
            if isRetired, let drainer = built.drainer { await drainer.stopObserving(owner: outboxObserver) }
        }

        /// Hands a first message that is only held in memory back to the composer, so a failed attach or a retired chat
        /// never loses it. Text the outbox saved is not held here, so nothing is sent twice.
        func giveBackFirstMessage() {
            guard let first = firstMessage else { return }
            firstMessage = nil
            returnedFiles += first.attachments
            prefill = first.text
        }

        /// The chat keeps the profile it first attached under. A later profile change, such as opening another bot, does
        /// not move it (WP-5).
        func pinProfile(using client: GatewayClient?) async {
            guard !profilePinned, let client else { return }
            // A nil active profile pins to the default by name, so a later change cannot move this chat (M4).
            pinnedProfile = ProfilePin.resolve(activeProfile: await client.activeProfile())
            profilePinned = true
        }
    }
#endif
