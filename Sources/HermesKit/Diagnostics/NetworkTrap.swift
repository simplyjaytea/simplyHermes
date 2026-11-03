#if DEBUG
    import Foundation

    /// Counts the network connections the app opens, per kind of transport: HTTP requests, WebSocket upgrades, terminal
    /// sockets, SSH connections and model-file downloads. A UI test reads the totals (WP-7, AT-2b). Each transport records
    /// itself where it opens, so a transport that does not record is missed; a Linux test fails when a file that opens a
    /// connection has no `NetworkTrap.record` (`NetworkTrapTests.everyFileThatOpensAConnectionRecordsIt`). The file is
    /// compiled in debug builds only, and every call site is wrapped the same way, so release builds never count.
    public enum NetworkTrap {
        /// Every site that records. The readout lists them in this order.
        public static let sites = ["http", "websocket", "terminal", "ssh", "download", "intercepted"]

        private static let lock = NSLock()
        nonisolated(unsafe) private static var openings: [String: Int] = [:]

        /// Connections opened since the process started, of every kind.
        public static var count: Int {
            lock.withLock { openings.values.reduce(0, +) }
        }

        /// Connections opened at one site.
        public static func count(at site: String) -> Int {
            lock.withLock { openings[site, default: 0] }
        }

        /// The per-site counts, for example `http=1 websocket=0 terminal=0 ssh=0 download=0`.
        public static var summary: String {
            sites.map { "\($0)=\(count(at: $0))" }.joined(separator: " ")
        }

        /// Records one connection opened at `site`.
        public static func record(_ site: String) {
            lock.withLock { openings[site, default: 0] += 1 }
        }

        nonisolated(unsafe) private static var gatewayStopped = false

        /// Whether a UI test has stopped the gateway. While it is stopped, the HTTP and WebSocket transports refuse to connect.
        public static var isGatewayStopped: Bool {
            lock.withLock { gatewayStopped }
        }

        /// Stops or starts the gateway for a UI test (WP-8, AT-1b and AT-3b). Stopping does not close a socket that is
        /// already open; it stops new connections, and the chat's status is set to no network path alongside it.
        public static func setGatewayStopped(_ stopped: Bool) {
            lock.withLock { gatewayStopped = stopped }
        }

        /// Throws the error a refused connection gives, while the gateway is stopped. Called where a transport connects.
        public static func failIfGatewayStopped() throws {
            if isGatewayStopped { throw URLError(.cannotConnectToHost) }
        }
    }
#endif
