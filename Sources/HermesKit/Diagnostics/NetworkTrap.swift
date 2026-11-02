#if DEBUG
    import Foundation

    /// Counts the network connections the app opens: each HTTP request, WebSocket upgrade, terminal socket and SSH
    /// connection. The total is shown in a hidden element that UI tests read (WP-7, AT-2b). The file is compiled in
    /// debug builds only, and every call site is wrapped the same way, so release builds never count.
    public enum NetworkTrap {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var openings: [String: Int] = [:]

        /// Connections opened since the process started, of every kind.
        public static var count: Int {
            lock.withLock { openings.values.reduce(0, +) }
        }

        /// Connections opened at one site: `http`, `websocket`, `terminal` or `ssh`.
        public static func count(at site: String) -> Int {
            lock.withLock { openings[site, default: 0] }
        }

        /// Records one connection opened at `site`.
        public static func record(_ site: String) {
            lock.withLock { openings[site, default: 0] += 1 }
        }
    }
#endif
