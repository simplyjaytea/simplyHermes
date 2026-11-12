#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// Where the app keeps its outgoing messages (WP-3). The App installs the chat cache's outbox at launch. Without an
    /// installed store, an in-memory one is used, which keeps nothing across a relaunch.
    @MainActor
    public enum OutboxServices {
        public static var store: any OutboxStore = {
            guard let cache = try? HermesCache() else { preconditionFailure("The in-memory cache cannot fail to open") }
            return cache.outbox
        }()

        /// Where New chats that have no server session yet are kept (board row 104). Nil keeps no queue for them.
        public static var placeholders: (any PlaceholderStore)?

        /// False when the store cannot keep messages across a relaunch. Sending is then refused with a status line,
        /// the same way offline chats are turned off when their file will not open, so nothing is lost silently.
        public static var isDurable = true

        /// Uses `store` for every chat from now on. `durable` says whether it keeps messages across a relaunch.
        public static func install(
            _ store: any OutboxStore, placeholders: (any PlaceholderStore)? = nil, durable: Bool = true
        ) {
            self.store = store
            self.placeholders = placeholders
            isDurable = durable
        }
    }
#endif
