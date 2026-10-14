import Foundation
import HermesKit
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func state(
    _ phase: LiveTurnState.Phase = .thinking,
    line: String = "Reading files",
    command: String? = nil
) -> LiveTurnState {
    LiveTurnState(
        phase: phase, botName: "Deploy bot", title: "Fix the deploy script", lastLine: line,
        pendingCommand: command, startedAt: start)
}

// MARK: - Content state

@Test func lastLineKeepsOnlyTheNewestNonEmptyLine() {
    #expect(state(line: "first\nsecond\n  third  \n\n").lastLine == "third")
}

@Test func longTextIsCutToTheLimits() {
    let long = String(repeating: "x", count: 5000)
    let cut = state(.waitingForApproval, line: long, command: long)
    #expect(cut.lastLine.count == LiveTurnState.lastLineLimit)
    #expect(cut.lastLine.hasPrefix("…"))
    #expect(cut.pendingCommand?.hasSuffix("…") == true)
    #expect(cut.pendingCommand?.count == LiveTurnState.commandLimit)
}

@Test func worstCaseStateFitsActivityKitLimit() throws {
    let long = String(repeating: "é", count: 5000)
    var worst = state(.waitingForApproval, line: long, command: long)
    worst.botName = String(repeating: "b", count: 60)
    worst.title = String(repeating: "t", count: 120)
    #expect(try worst.encodedSize() < LiveTurnState.maximumEncodedSize)
}

@Test func approvalButtonsNeedACommand() {
    #expect(state(.waitingForApproval, command: "rm -rf build").needsApproval)
    #expect(!state(.waitingForApproval).needsApproval)
    #expect(!state(.runningTool, command: "ls").needsApproval)
}

@Test func finishedPhases() {
    let finished = LiveTurnState.Phase.allCases.filter(\.isFinished)
    #expect(finished == [.done, .failed, .stopped])
}

@Test func botCountIsAtLeastOne() {
    let room = LiveTurnState(
        phase: .thinking, botName: "Room", title: "t", lastLine: "", startedAt: start, activeBotCount: 0)
    #expect(room.activeBotCount == 1)
}

// MARK: - Throttle

@Test func firstUpdateGoesOutAtOnce() {
    let throttle = LiveUpdateThrottle()
    #expect(throttle.decide(state(), now: start) == .sendNow)
}

@Test func tokenUpdatesWaitForTheInterval() {
    var throttle = LiveUpdateThrottle(minimumInterval: 1)
    throttle.markSent(state(), at: start)
    let soon = start.addingTimeInterval(0.3)
    #expect(throttle.decide(state(line: "more"), now: soon) == .sendAt(start.addingTimeInterval(1)))
    #expect(throttle.decide(state(line: "more"), now: start.addingTimeInterval(1)) == .sendNow)
}

@Test func phaseChangesAndApprovalsSkipTheThrottle() {
    var throttle = LiveUpdateThrottle(minimumInterval: 1)
    throttle.markSent(state(), at: start)
    let soon = start.addingTimeInterval(0.1)
    #expect(throttle.decide(state(.runningTool), now: soon) == .sendNow)
    #expect(throttle.decide(state(command: "make deploy"), now: soon) == .sendNow)
}

// MARK: - Buttons

@Test func buttonsFollowThePhase() {
    #expect(LiveTurnAction.available(for: state()) == [.stop])
    #expect(LiveTurnAction.available(for: state(.waitingForApproval, command: "make")) == [.stop, .deny, .approve])
    #expect(LiveTurnAction.available(for: state(.done)).isEmpty)
}
