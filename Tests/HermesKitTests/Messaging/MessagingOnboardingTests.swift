import HermesKit
import Testing

/// The pairing state machine: each path through a Telegram or WhatsApp pairing, and events that do not fit.
@Suite struct MessagingOnboardingTests {
    @Test func happyPathStartsWaitsLinksAppliesAndFinishes() {
        var machine = MessagingOnboardingMachine()
        #expect(machine.handle(.start) == .start)
        #expect(machine.phase == .starting && machine.pairingID == nil)
        #expect(machine.handle(.started(pairingID: "p1")) == .poll(pairingID: "p1"))
        #expect(machine.phase == .waiting(pairingID: "p1"))
        #expect(machine.handle(.polled(linked: false)) == .poll(pairingID: "p1"))
        #expect(machine.phase == .waiting(pairingID: "p1"))
        #expect(machine.handle(.polled(linked: true)) == nil)
        #expect(machine.phase == .linked(pairingID: "p1"))
        let apply = machine.handle(.apply(allowedUserIds: ["11", "12"]))
        #expect(apply == .apply(pairingID: "p1", allowedUserIds: ["11", "12"]))
        #expect(machine.phase == .applying(pairingID: "p1"))
        #expect(machine.handle(.applied) == nil)
        #expect(machine.phase == .finished && machine.pairingID == nil)
    }

    @Test func failedStartCanBeRetried() {
        var machine = MessagingOnboardingMachine()
        machine.handle(.start)
        #expect(machine.handle(.startFailed(message: "Server refused")) == nil)
        #expect(machine.phase == .failed(pairingID: nil, message: "Server refused"))
        #expect(machine.handle(.start) == .start)
        #expect(machine.phase == .starting)
    }

    @Test func failedPollKeepsThePairingForCancel() {
        var machine = MessagingOnboardingMachine(phase: .waiting(pairingID: "p2"))
        #expect(machine.handle(.pollFailed(message: "Timed out")) == nil)
        #expect(machine.phase == .failed(pairingID: "p2", message: "Timed out"))
        #expect(machine.pairingID == "p2")
        #expect(machine.handle(.start) == nil, "a new start waits until the old pairing is cancelled")
        #expect(machine.phase == .failed(pairingID: "p2", message: "Timed out"))
        #expect(machine.handle(.cancel) == .cancel(pairingID: "p2"))
        #expect(machine.phase == .cancelled)
    }

    @Test func failedApplyKeepsThePairingForCancel() {
        var machine = MessagingOnboardingMachine(phase: .linked(pairingID: "p3"))
        machine.handle(.apply(allowedUserIds: ["1"]))
        #expect(machine.handle(.applyFailed(message: "Invalid user id")) == nil)
        #expect(machine.phase == .failed(pairingID: "p3", message: "Invalid user id"))
        #expect(machine.handle(.cancel) == .cancel(pairingID: "p3"))
    }

    @Test func cancelWhileWaitingOrLinkedSendsTheDelete() {
        var waiting = MessagingOnboardingMachine(phase: .waiting(pairingID: "p4"))
        #expect(waiting.handle(.cancel) == .cancel(pairingID: "p4") && waiting.phase == .cancelled)
        var linked = MessagingOnboardingMachine(phase: .linked(pairingID: "p5"))
        #expect(linked.handle(.cancel) == .cancel(pairingID: "p5") && linked.phase == .cancelled)
    }

    @Test func cancelDuringStartCancelsTheLatePairing() {
        var machine = MessagingOnboardingMachine()
        machine.handle(.start)
        #expect(machine.handle(.cancel) == nil)
        #expect(machine.phase == .cancelled)
        #expect(machine.handle(.started(pairingID: "p6")) == .cancel(pairingID: "p6"))
        #expect(machine.phase == .cancelled, "a late start answer does not restart the pairing")
    }

    @Test func eventsThatDoNotFitTheirPhaseChangeNothing() {
        var idle = MessagingOnboardingMachine()
        #expect(idle.handle(.polled(linked: true)) == nil && idle.phase == .idle)
        #expect(idle.handle(.cancel) == nil && idle.phase == .idle)
        var waiting = MessagingOnboardingMachine(phase: .waiting(pairingID: "p7"))
        #expect(waiting.handle(.apply(allowedUserIds: ["1"])) == nil)
        #expect(waiting.handle(.start) == nil && waiting.phase == .waiting(pairingID: "p7"))
        var applying = MessagingOnboardingMachine(phase: .applying(pairingID: "p8"))
        #expect(applying.handle(.cancel) == nil && applying.phase == .applying(pairingID: "p8"))
        var finished = MessagingOnboardingMachine(phase: .finished)
        #expect(finished.handle(.apply(allowedUserIds: ["1"])) == nil && finished.phase == .finished)
    }

    @Test func aFinishedOrCancelledPairingCanStartAgain() {
        var finished = MessagingOnboardingMachine(phase: .finished)
        #expect(finished.handle(.start) == .start && finished.phase == .starting)
        var cancelled = MessagingOnboardingMachine(phase: .cancelled)
        #expect(cancelled.handle(.start) == .start && cancelled.phase == .starting)
    }
}
