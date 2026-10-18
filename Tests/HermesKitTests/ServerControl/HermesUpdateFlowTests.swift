import Foundation
import HermesKit
import Testing

/// The update run on one server: check, update, wait for a new receipt, then the version check.
@Suite struct HermesUpdateFlowTests {
    private let oldReceipt: JSONValue = .object(["run": .string("1")])
    private let newReceipt: JSONValue = .object(["run": .string("2")])
    private let available = HermesUpdateCheck(
        installMethod: "git", currentVersion: "0.19.0", behind: 4, updateAvailable: true, canApply: true,
        updateCommand: "hermes update")

    @Test func upToDateStartsNothing() async throws {
        let server = ServerControlUpdateServer(
            check: HermesUpdateCheck(behind: 0, updateAvailable: false), polls: [.absent])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .upToDate)
        #expect(server.started == 0 && server.checkForces == [true])
    }

    @Test func aManualInstallIsNotUpdatedFromTheApp() async throws {
        let check = HermesUpdateCheck(
            installMethod: "apt", updateAvailable: true, canApply: false, updateCommand: "sudo apt upgrade hermes")
        let server = ServerControlUpdateServer(check: check, polls: [.absent])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .manualUpdateNeeded(command: "sudo apt upgrade hermes", message: nil))
        #expect(server.started == 0)
    }

    @Test func anUnclearCheckIsReportedNotAssumedFine() async throws {
        let check = HermesUpdateCheck(updateAvailable: nil, message: "git is not available")
        let server = ServerControlUpdateServer(check: check, polls: [.absent])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .checkUnclear(message: "git is not available"))
        #expect(server.started == 0)
    }

    @Test func updateWaitsForANewReceiptThroughARestart() async throws {
        let server = ServerControlUpdateServer(
            check: available,
            polls: [.receipt(oldReceipt), .unreachable, .receipt(oldReceipt), .receipt(newReceipt)],
            statuses: [nil, serverControlStatus(release: "2026.9.24")])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .finished(compatibility: .compatible, receipt: newReceipt))
        #expect(server.started == 1)
        #expect(clock.recorded.allSatisfy { $0 == 3 })
    }

    @Test func aReceiptThatIsTheSameAsBeforeDoesNotCount() async throws {
        let server = ServerControlUpdateServer(
            check: available, polls: [.receipt(oldReceipt)], statuses: [serverControlStatus(release: "2026.9.24")])
        let flow = HermesUpdateFlow(pollInterval: 3, timeout: 30)
        let clock = ServerControlVirtualClock()
        let outcome = try await flow.checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .timedOut)
        #expect(clock.now() == 30)
    }

    @Test func noReceiptBeforeTheRunAndOneAfterCounts() async throws {
        let server = ServerControlUpdateServer(
            check: available, polls: [.absent, .absent, .receipt(newReceipt)],
            statuses: [serverControlStatus(release: "2026.9.24")])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .finished(compatibility: .compatible, receipt: newReceipt))
    }

    @Test func aVersionThatIsStillOldIsReportedAfterTheUpdate() async throws {
        let server = ServerControlUpdateServer(
            check: available, polls: [.absent, .receipt(newReceipt)],
            statuses: [serverControlStatus(release: "2026.9.1")])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .finished(compatibility: .updateRequired(found: "release 2026.9.1"), receipt: newReceipt))
    }

    @Test func anErrorAnswerIsUnclearAndShowsItsMessage() async throws {
        let message = "Couldn't reach the update source — try again later."
        let server = ServerControlUpdateServer(
            check: HermesUpdateCheck(updateAvailable: false, message: message), polls: [.absent])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .checkUnclear(message: message))
        #expect(server.started == 0)
    }

    @Test func aDeclinedUpdateStartsNothing() async throws {
        let server = ServerControlUpdateServer(check: available, polls: [.absent])
        let asked = ServerControlCallLog()
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { check in
            asked.record(check.currentVersion ?? "")
            return false
        }
        #expect(outcome == .skipped)
        #expect(asked.names == ["0.19.0"] && server.started == 0)
    }

    @Test func theUserIsAskedOnlyWhenAnUpdateCanRun() async throws {
        let asked = ServerControlCallLog()
        let upToDate = ServerControlUpdateServer(
            check: HermesUpdateCheck(behind: 0, updateAvailable: false), polls: [.absent])
        let manual = ServerControlUpdateServer(
            check: HermesUpdateCheck(installMethod: "apt", updateAvailable: true, canApply: false), polls: [.absent])
        let clock = ServerControlVirtualClock()
        _ = try await HermesUpdateFlow().checkAndApply(upToDate.steps, clock: clock) { _ in
            asked.record("up to date")
            return true
        }
        _ = try await HermesUpdateFlow().checkAndApply(manual.steps, clock: clock) { _ in
            asked.record("manual")
            return true
        }
        #expect(asked.names.isEmpty)
    }

    @Test func aBaselineReadThatFailsFirstIsRetried() async throws {
        // The first read fails. Without a retry, the old receipt would count as new when a later read answers it.
        let server = ServerControlUpdateServer(
            check: available, polls: [.unreachable, .receipt(oldReceipt), .receipt(oldReceipt), .receipt(newReceipt)],
            statuses: [serverControlStatus(release: "2026.9.24")])
        let clock = ServerControlVirtualClock()
        let outcome = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        #expect(outcome == .finished(compatibility: .compatible, receipt: newReceipt))
        #expect(server.started == 1)
    }

    @Test func anUnreadableBaselineStartsNoUpdate() async throws {
        let server = ServerControlUpdateServer(check: available, polls: [.unreachable])
        let clock = ServerControlVirtualClock()
        var thrown: (any Error)?
        do {
            _ = try await HermesUpdateFlow().checkAndApply(server.steps, clock: clock) { _ in true }
        } catch {
            thrown = error
        }
        #expect(thrown as? ServerControlError == ServerControlError.notConnected)
        #expect(server.started == 0 && clock.now() == 60)
    }

    @Test func thePlanDefaultsArePollEveryThreeSecondsForFifteenMinutes() {
        let flow = HermesUpdateFlow()
        #expect(flow.pollInterval == 3 && flow.timeout == 900)
    }
}
