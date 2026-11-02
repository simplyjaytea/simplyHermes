#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One local chat on this iPhone as the screen shows it (WP-7). It needs no server and no connection.
    @MainActor
    @Observable
    public final class LocalChatModel {
        /// The chat's id. It is the `ChatBackend.local(chatID:)` of this chat.
        public let chatID: UUID
        /// The chat as it is now.
        public private(set) var snapshot = LocalChatSnapshot()

        @ObservationIgnored private let controller: Task<LocalChatController, Never>
        @ObservationIgnored private var follow: Task<Void, Never>?

        /// Opens the local chat `chatID`. Its saved messages load at once; a chat not yet saved is created by its first
        /// message.
        public init(chatID: UUID, services: LocalChatServices) {
            self.chatID = chatID
            let controller = Task {
                await LocalChatController(store: services.store, answerer: services.answerer, chatID: chatID)
            }
            self.controller = controller
            follow = Task { [weak self] in
                let open = await controller.value
                for await next in await open.states() {
                    guard let self else { return }
                    self.snapshot = next
                }
            }
        }

        /// Saves `text` and has the on-device model answer it in the background. Returns true once the message is saved,
        /// so the composer may clear; false leaves the text where it is.
        public func submit(_ text: String) async -> Bool {
            let open = await controller.value
            return await open.submit(text)
        }

        /// Asks the model again for the newest message, when that message has no reply. Adds one reply at most.
        public func retry() {
            Task {
                let open = await controller.value
                await open.retry()
            }
        }

        /// Stops following the chat when its screen goes away. A send already on its way still finishes.
        public func stop() {
            follow?.cancel()
            follow = nil
        }
    }
#endif
