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

        /// Uses `store` for every chat from now on.
        public static func install(_ store: any OutboxStore) {
            self.store = store
        }
    }
#endif
