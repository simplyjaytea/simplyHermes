import Foundation
import HermesKit

/// A clock that moves only when a sleep asks it to, so the waits run in virtual seconds.
final class ServerControlVirtualClock: GatewayClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0.0
    private var sleeps: [Double] = []

    func now() -> Double { lock.withLock { current } }

    /// Every sleep requested, in order.
    var recorded: [Double] { lock.withLock { sleeps } }

    func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        lock.withLock {
            current += seconds
            sleeps.append(seconds)
        }
    }
}

/// Answers probes from a script. Calls past the script answer `false`.
final class ServerControlProbeScript: @unchecked Sendable {
    private let lock = NSLock()
    private let answers: [Bool]
    private var calls = 0

    init(_ answers: [Bool]) {
        self.answers = answers
    }

    func next() -> Bool {
        lock.withLock {
            calls += 1
            return calls <= answers.count ? answers[calls - 1] : false
        }
    }

    var count: Int { lock.withLock { calls } }
}

/// Records names in the order they arrive.
final class ServerControlCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ name: String) {
        lock.withLock { entries.append(name) }
    }

    var names: [String] { lock.withLock { entries } }
}

/// A Hermes update on one server, scripted: checks, receipt polls and version answers come from fixed lists.
final class ServerControlUpdateServer: @unchecked Sendable {
    private let lock = NSLock()
    private let check: HermesUpdateCheck
    private var polls: [HermesUpdatePoll]
    /// `nil` in the list is a failed read (the server is still restarting).
    private var statuses: [ServerStatus?]
    private var forces: [Bool] = []
    private var startCount = 0

    init(check: HermesUpdateCheck, polls: [HermesUpdatePoll], statuses: [ServerStatus?] = []) {
        self.check = check
        self.polls = polls
        self.statuses = statuses
    }

    /// The steps the flow runs against this server.
    var steps: HermesUpdateSteps {
        HermesUpdateSteps(
            check: { force in
                self.lock.withLock { self.forces.append(force) }
                return self.check
            },
            poll: { self.nextPoll() },
            startUpdate: { self.lock.withLock { self.startCount += 1 } },
            status: {
                guard let next = self.nextStatus() else { throw ServerControlError.notConnected }
                return next
            })
    }

    /// The `force` value of each check, in order.
    var checkForces: [Bool] { lock.withLock { forces } }

    /// How many updates were started.
    var started: Int { lock.withLock { startCount } }

    private func nextPoll() -> HermesUpdatePoll {
        lock.withLock {
            guard polls.count > 1 else { return polls.first ?? .unreachable }
            return polls.removeFirst()
        }
    }

    private func nextStatus() -> ServerStatus? {
        lock.withLock {
            guard !statuses.isEmpty else { return nil }
            return statuses.removeFirst()
        }
    }
}

/// A status with only the release date set, for the version check.
func serverControlStatus(release: String) -> ServerStatus {
    ServerControlStatus(releaseDate: release, latestConfigVersion: 50).server
}
