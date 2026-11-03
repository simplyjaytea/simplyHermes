#if canImport(UIKit)
    import HermesKit
    import Network
    import Observation

    /// The phone's network path, from `NWPathMonitor`. One shared monitor feeds every chat's status, so a missing network
    /// is seen at once (plan WP-8: "Can't reach" within 2 s when there is no network path).
    @MainActor
    @Observable
    public final class NetworkMonitor {
        /// The app's monitor, started on first use.
        @MainActor public static let shared: NetworkMonitor = {
            let monitor = NetworkMonitor()
            monitor.start()
            return monitor
        }()

        /// `unknown` until the first report. `requiresConnection` counts as unknown: the path is not known to be down.
        public private(set) var path: NetworkPath = .unknown
        @ObservationIgnored private var monitor: NWPathMonitor?

        init() {}

        private func start() {
            guard monitor == nil else { return }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { update in
                let mapped = Self.map(update.status)
                Task { @MainActor in NetworkMonitor.shared.receive(mapped) }
            }
            monitor.start(queue: DispatchQueue(label: "simplyHermes.network-path"))
            self.monitor = monitor
        }

        /// Maps the system's status onto the status core's path.
        nonisolated static func map(_ status: NWPath.Status) -> NetworkPath {
            switch status {
            case .satisfied: .satisfied
            case .unsatisfied: .unsatisfied
            case .requiresConnection: .unknown
            @unknown default: .unknown
            }
        }

        /// Applies a system report. In debug builds a path a UI test pinned stays in place, so the system's first report
        /// cannot overwrite it.
        private func receive(_ mapped: NetworkPath) {
            #if DEBUG
                if let pinnedPath {
                    path = pinnedPath
                    return
                }
            #endif
            path = mapped
        }

        #if DEBUG
            /// The path a UI test pinned, if any. Nil means the system's reports apply.
            @ObservationIgnored private var pinnedPath: NetworkPath?

            /// Pins the path a UI test needs (WP-8, AT-1b and AT-3b). It stays until the test pins another.
            public func setPathForTesting(_ path: NetworkPath) {
                pinnedPath = path
                self.path = path
            }
        #endif
    }
#endif
