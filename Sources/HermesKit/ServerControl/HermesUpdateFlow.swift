import Foundation

/// What one receipt poll found.
public enum HermesUpdatePoll: Sendable, Equatable {
    /// The server answered with the latest receipt.
    case receipt(JSONValue)
    /// The server answered, and no update has left a receipt yet.
    case absent
    /// No answer. The server is usually restarting, so the poll goes on.
    case unreachable
}

/// The steps one server's update runs. The screens and the fleet update build it from a ``ServerControlBackend``;
/// tests build it from fakes.
public struct HermesUpdateSteps: Sendable {
    /// `GET /api/hermes/update/check`. The flag is `force`.
    public var check: @Sendable (_ force: Bool) async throws -> HermesUpdateCheck
    /// Reads the latest receipt. Never throws: a failed read is ``HermesUpdatePoll/unreachable``.
    public var poll: @Sendable () async -> HermesUpdatePoll
    /// `POST /api/hermes/update`.
    public var startUpdate: @Sendable () async throws -> Void
    /// Reads the release and config fields again, after the update.
    public var status: @Sendable () async throws -> ServerStatus

    /// Creates the steps.
    public init(
        check: @escaping @Sendable (_ force: Bool) async throws -> HermesUpdateCheck,
        poll: @escaping @Sendable () async -> HermesUpdatePoll,
        startUpdate: @escaping @Sendable () async throws -> Void,
        status: @escaping @Sendable () async throws -> ServerStatus
    ) {
        self.check = check
        self.poll = poll
        self.startUpdate = startUpdate
        self.status = status
    }
}

/// How one server's update run ended.
public enum HermesUpdateRunOutcome: Sendable, Equatable {
    /// The check found no update.
    case upToDate
    /// An update exists, but this install cannot apply it from the app. Run `command` by hand.
    case manualUpdateNeeded(command: String?, message: String?)
    /// The check could not tell whether an update exists.
    case checkUnclear(message: String?)
    /// The user chose not to update this server. Nothing was started.
    case skipped
    /// The update left a new receipt. `compatibility` is the version check run afterwards.
    case finished(compatibility: ServerCompatibility, receipt: JSONValue)
    /// No new receipt, or no answer to the version check, within the window.
    case timedOut
}

/// Runs a Hermes update on one server: check, update, wait for the receipt, then re-run the version check.
public struct HermesUpdateFlow: Sendable, Equatable {
    /// Seconds between polls: 3.
    public static let defaultPollInterval: Double = 3
    /// Longest wait for the receipt: 15 minutes.
    public static let defaultTimeout: Double = 900
    /// Longest wait for the receipt read before the update: 60 seconds.
    private static let baselineWindow: Double = 60

    /// Seconds between polls.
    public var pollInterval: Double
    /// Longest wait for the receipt, in seconds.
    public var timeout: Double

    /// Creates a flow with the defaults: poll every 3 s, give up after 15 minutes.
    public init(
        pollInterval: Double = HermesUpdateFlow.defaultPollInterval, timeout: Double = HermesUpdateFlow.defaultTimeout
    ) {
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// Checks first (forced), updates only when the check says an update exists, this install can apply it, and
    /// `confirm` says yes. `confirm` runs after the check, with the check's answer, so the user sees what will change.
    public func checkAndApply(
        _ steps: HermesUpdateSteps, clock: any GatewayClock, confirm: @Sendable (HermesUpdateCheck) async -> Bool
    ) async throws -> HermesUpdateRunOutcome {
        let check = try await steps.check(true)
        guard check.updateAvailable == true else {
            if check.isUpToDate { return .upToDate }
            return .checkUnclear(message: check.message)
        }
        guard check.canApply == true else {
            return .manualUpdateNeeded(command: check.updateCommand, message: check.message)
        }
        guard await confirm(check) else { return .skipped }
        return try await apply(steps, clock: clock)
    }

    /// Starts the update and waits for a receipt that differs from the one read before. Then reads the version again,
    /// once the server answers. Throws when no receipt read answers before the update, so the update does not start.
    public func apply(_ steps: HermesUpdateSteps, clock: any GatewayClock) async throws -> HermesUpdateRunOutcome {
        let baseline = try await baselineReceipt(steps, clock: clock)
        try await steps.startUpdate()
        let start = clock.now()
        var finished: JSONValue?
        while true {
            try await clock.sleep(seconds: pollInterval)
            if finished == nil, case .receipt(let receipt) = await steps.poll(), receipt != baseline {
                finished = receipt
            }
            if let receipt = finished, let status = try? await steps.status() {
                return .finished(compatibility: ServerCompatibility.check(status), receipt: receipt)
            }
            if clock.now() - start >= timeout { return .timedOut }
        }
    }

    /// The receipt before the update. A read that does not answer is retried every poll interval, for up to 60 seconds.
    /// If no read answers, the update does not start: a later read of the old receipt would then count as new.
    private func baselineReceipt(_ steps: HermesUpdateSteps, clock: any GatewayClock) async throws -> JSONValue? {
        let start = clock.now()
        while true {
            switch await steps.poll() {
            case .receipt(let receipt):
                return receipt
            case .absent:
                return nil
            case .unreachable:
                if clock.now() - start >= Self.baselineWindow { throw ServerControlError.notConnected }
                try await clock.sleep(seconds: pollInterval)
            }
        }
    }
}
