#if canImport(UIKit)
    import HermesKit
    import Observation

    /// Where the Hermes update screen stands.
    public enum HermesUpdatePhase: Sendable, Equatable {
        case idle
        /// The update check runs.
        case checking
        /// The update runs. The server may restart, so the app waits for the receipt.
        case updating
        /// A new receipt arrived. The result shows the version check and the receipt.
        case finished
        /// No receipt arrived within the window.
        case timedOut
        /// The check or the update failed, in words.
        case failed(String)
    }

    /// The Hermes update screen (Settings > Server > Hermes update): the check, the update behind a confirm, the wait
    /// for the receipt, then the version check and the receipt (WP-54).
    @MainActor
    @Observable
    public final class HermesUpdateModel {
        /// The last check, kept on screen while the update runs.
        public private(set) var check: HermesUpdateCheck?
        public private(set) var phase: HermesUpdatePhase = .idle
        /// What the version check found after an update.
        public private(set) var versionText: String?
        /// The receipt of the last update, as rows.
        public private(set) var receiptRows: [ServerStatsRow] = []

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let clock: any GatewayClock

        public init(connections: ConnectionsModel, clock: any GatewayClock = SystemGatewayClock()) {
            self.connections = connections
            self.clock = clock
        }

        /// True while a check or an update runs.
        public var isBusy: Bool {
            phase == .checking || phase == .updating
        }

        /// Reads the update check. `force` asks the server to look again rather than answer from its cache.
        public func loadCheck(force: Bool) async {
            guard connections.manager != nil, !isBusy else { return }
            guard let backend = serverControlBackend(connections, connections.active) else {
                phase = .failed("Choose a server in Settings > Servers.")
                return
            }
            phase = .checking
            do {
                let rest = try await backend.rest()
                check = try await rest.hermesUpdateCheck(force: force)
                phase = .idle
            } catch {
                phase = .failed(ServerControlError.describe(error))
            }
        }

        /// Starts the update, which the user confirmed. Waits for the receipt, then re-runs the version check.
        public func startUpdate() async {
            guard connections.manager != nil, !isBusy else { return }
            guard let backend = serverControlBackend(connections, connections.active) else { return }
            phase = .updating
            versionText = nil
            receiptRows = []
            do {
                let outcome = try await HermesUpdateFlow().apply(backend.updateSteps(), clock: clock)
                switch outcome {
                case .finished(let compatibility, let receipt):
                    versionText = Self.versionText(compatibility)
                    receiptRows = ServerStatsRows.rows(from: receipt)
                    phase = .finished
                case .timedOut:
                    phase = .timedOut
                default:
                    phase = .idle
                }
            } catch {
                phase = .failed(ServerControlError.describe(error))
            }
            if let rest = await backend.connectedRest(), let refreshed = try? await rest.hermesUpdateCheck(force: true)
            {
                check = refreshed
            }
        }

        static func versionText(_ compatibility: ServerCompatibility) -> String {
            switch compatibility {
            case .compatible:
                return "The version check passed."
            case .updateRequired(let found):
                return "Still too old (\(found)). Check the server's update."
            case .newerThanApp:
                return "The server is newer than this app. Update simplyHermes."
            }
        }

        /// A model with fixed state, for previews.
        static func preview(
            check: HermesUpdateCheck?, phase: HermesUpdatePhase = .idle
        ) -> HermesUpdateModel {
            let model = HermesUpdateModel(connections: .preview())
            model.check = check
            model.phase = phase
            return model
        }
    }

    extension HermesUpdateCheck {
        /// A git install with an update available, for previews.
        static var sampleAvailable: HermesUpdateCheck {
            HermesUpdateCheck(
                installMethod: "git", currentVersion: "git.d97007c", behind: -1, updateAvailable: true, canApply: true,
                updateCommand: "hermes update")
        }
    }
#endif
