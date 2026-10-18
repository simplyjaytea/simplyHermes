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

    /// Checks first (forced), updates only when the check says an update exists and this install can apply it.
    public func checkAndApply(_ steps: HermesUpdateSteps, clock: any GatewayClock) async throws
        -> HermesUpdateRunOutcome
    {
        let check = try await steps.check(true)
        guard check.updateAvailable == true else {
            if check.updateAvailable == false { return .upToDate }
            return .checkUnclear(message: check.message)
        }
        guard check.canApply == true else {
            return .manualUpdateNeeded(command: check.updateCommand, message: check.message)
        }
        return try await apply(steps, clock: clock)
    }

    /// Starts the update and waits for a receipt that differs from the one read before. Then reads the version again,
    /// once the server answers.
    public func apply(_ steps: HermesUpdateSteps, clock: any GatewayClock) async throws -> HermesUpdateRunOutcome {
        let baseline = Self.receipt(of: await steps.poll())
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

    private static func receipt(of poll: HermesUpdatePoll) -> JSONValue? {
        if case .receipt(let receipt) = poll { return receipt }
        return nil
    }
}
