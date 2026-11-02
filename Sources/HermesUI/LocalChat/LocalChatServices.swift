#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// What local chats need from the app (WP-7): where they are kept and which model answers. The app installs it at
    /// launch over the cache file. Until then local chats are off, so previews and snapshot tests never open a file.
    @MainActor
    public final class LocalChatServices {
        /// The installed services. Nil keeps local chats off.
        public static var shared: LocalChatServices?

        /// Where local chats are kept.
        public let store: any LocalChatStore
        /// The model for the next reply. It is asked for every reply, so a model chosen in Settings applies at once.
        public let answerer: @Sendable () -> any LocalChatAnswerer

        /// Creates the services.
        public init(store: any LocalChatStore, answerer: @escaping @Sendable () -> any LocalChatAnswerer) {
            self.store = store
            self.answerer = answerer
        }

        /// Installs the services over the app's cache, so local chats live in the same file as the chat list.
        public static func install(cache: HermesCache, answerer: @escaping @Sendable () -> any LocalChatAnswerer) {
            shared = LocalChatServices(store: cache.localChats, answerer: answerer)
        }
    }
#endif
