import Foundation
import HermesKit
import XCTest

/// WP-16a CI gate: every recorded fixture replays through the reducer into a consistent transcript.
final class TranscriptFixtureTests: XCTestCase {
    private func fixtureNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: FixtureFiles.directory.path)
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
    }

    /// Invariants that hold for every fixture and every session in it.
    func testEveryFixtureReplaysConsistently() throws {
        for name in try fixtureNames() {
            let replay = try FixtureTranscripts.replay(name)
            for (session, state) in replay.sessions {
                let label = "\(name) \(session)"
                XCTAssertEqual(Set(state.items.map(\.id)).count, state.items.count, "\(label): duplicate item ids")
                for completion in replay.completions[session] ?? [] {
                    guard let text = completion.text, !text.isEmpty else { continue }
                    XCTAssertTrue(
                        state.assistantEntries.contains { $0.text == text },
                        "\(label): final text \"\(text)\" is not a segment: \(state.assistantEntries.map(\.text))")
                }
                if replay.completions[session]?.isEmpty == false, state.turn == nil {
                    XCTAssertFalse(state.assistantEntries.contains(where: \.isStreaming), "\(label): still streaming")
                }
                for tool in state.toolEntries {
                    XCTAssertNotEqual(tool.phase, .generating, "\(label): tool \(tool.name) never started")
                }
            }
        }
    }

    /// Applying a whole fixture in one batch (with delta coalescing) gives the same state as one action at a time.
    func testBatchedReplayMatchesStepByStep() throws {
        for name in try fixtureNames() {
            let single = try FixtureTranscripts.replay(name)
            let batched = try FixtureTranscripts.replay(name, batched: true)
            for (session, state) in single.sessions {
                XCTAssertEqual(batched.sessions[session], state, "\(name) \(session)")
            }
        }
    }

    func testSimpleChat() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("chat_simple.jsonl").sessions["5fc4489b"])
        XCTAssertEqual(state.shape, ["user", "assistant"])
        XCTAssertEqual(state.userEntries.first?.text, "hello [[scenario:text]]")
        XCTAssertEqual(state.userEntries.first?.delivery, .sent)
        XCTAssertNotNil(state.userEntries.first?.rowID)
        // The fixture ends with `session.history`, so the rows come from storage.
        XCTAssertEqual(state.items.map(\.id), ["row-125", "row-126"])
        XCTAssertEqual(state.assistantEntries.first?.text, "Hello from the fake LLM. This reply is scripted.")
        XCTAssertNil(state.turn)
        XCTAssertNotNil(state.title)
        XCTAssertNotNil(state.usage)
    }

    func testRefusedEditStaysAsFailedRow() throws {
        var state = try XCTUnwrap(FixtureTranscripts.replay("rewind.jsonl").sessions["3a8016f6"])
        state.apply(.userSubmitted(localID: "X1", text: "again", truncateBeforeRowID: 159))
        state.apply(.submitFailed(localID: "X1", message: "stale row"))
        XCTAssertEqual(state.userEntries.last?.delivery, .failed("stale row"))
        XCTAssertEqual(state.userEntries.first?.rowID, 159, "a refused edit removes nothing")
        XCTAssertEqual(state.userEntries.count, 3)
    }

    func testToolCallSplitsSegments() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("chat_tool_call.jsonl").sessions["d6f5399c"])
        XCTAssertEqual(state.shape, ["user", "assistant", "tool:terminal", "assistant"])
        let tool = try XCTUnwrap(state.toolEntries.first)
        XCTAssertEqual(tool.toolID, "call_11438fb80bf2")
        XCTAssertEqual(tool.phase, .completed)
        XCTAssertEqual(tool.context, "echo testbed-tool-ok")
        XCTAssertEqual(tool.result?["output"]?.stringValue, "testbed-tool-ok")
        XCTAssertNotNil(tool.durationSeconds)
        XCTAssertEqual(
            state.assistantEntries.map(\.text), ["Running a command.", "The command printed testbed-tool-ok."])
        XCTAssertEqual(state.assistantEntries.last?.rowID, 130)
        XCTAssertEqual(state.userEntries.first?.rowID, 127)
        XCTAssertFalse(
            state.items.contains { $0.id == "tool-call_11438fb80bf2" }, "the tool.generating row keeps its id")
    }

    func testApprovalOpensAndClosesACard() throws {
        let records = try FixtureFiles.load().filter { $0.file == "approval.jsonl" }
        let requestLine = try XCTUnwrap(
            records.first { if case .request(let request) = $0.frame { request.method == "approval" } else { false } })
        // Replay up to and including the approval request: one open card.
        var partial = TranscriptState(liveSessionID: "6558c086")
        for record in records where record.line <= requestLine.line {
            switch record.frame {
            case .event(let envelope): partial.apply(.event(envelope, replayed: false))
            case .request(let request) where record.dir == "in":
                partial.apply(.serverRequest(try ServerRequest(request: request)))
            default: break
            }
        }
        XCTAssertEqual(partial.openRequests.count, 1)
        XCTAssertEqual(partial.openRequests.first?.approvalRequestID, "da54646f35fc43e0aea8fef898bc89d0")
        XCTAssertEqual(partial.turn?.activeTool, "terminal")
        // The full replay answers it.
        let state = try XCTUnwrap(FixtureTranscripts.replay("approval.jsonl").sessions["6558c086"])
        XCTAssertTrue(state.openRequests.isEmpty)
        XCTAssertEqual(state.assistantEntries.first?.reasoning, "I will delete a scratch file.")
        XCTAssertEqual(state.assistantEntries.last?.reasoning, "Approval flow finished.")
    }

    func testApprovalAnsweredElsewhereIsCancelled() throws {
        let replay = try FixtureTranscripts.replay("approval_answered_elsewhere.jsonl")
        let state = try XCTUnwrap(replay.sessions["7952dcc4"])
        XCTAssertTrue(state.openRequests.isEmpty, "request.cancel dismisses the card")
    }

    func testClarifyRequestIsTyped() throws {
        let records = try FixtureFiles.load().filter { $0.file == "clarify.jsonl" }
        var state = TranscriptState(liveSessionID: "20f3019b")
        for record in records {
            if case .request(let request) = record.frame, record.dir == "in" {
                state.apply(.serverRequest(try ServerRequest(request: request)))
            }
        }
        guard case .clarify(_, let clarify) = state.openRequests.first?.request else {
            return XCTFail("no clarify card")
        }
        XCTAssertEqual(clarify.questions.map(\.qid), ["q0", "q1"])
    }

    func testInterruptKeepsPartialText() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("interrupt.jsonl").sessions["32ada97d"])
        let reply = try XCTUnwrap(state.assistantEntries.last)
        XCTAssertEqual(reply.status, .interrupted)
        XCTAssertFalse(reply.isStreaming)
        XCTAssertNil(state.turn)
    }

    func testSubagentLifecycle() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("subagents.jsonl").sessions["a3d65ee3"])
        let child = try XCTUnwrap(state.subagents.first)
        XCTAssertEqual(state.subagents.count, 1)
        XCTAssertEqual(child.id, "sa-0-094acbf9")
        XCTAssertEqual(child.goal, "say hello")
        XCTAssertEqual(child.status, .completed)
        XCTAssertEqual(child.summary, "Hello from the fake LLM. This reply is scripted.")
    }

    func testProviderRetryShowsStatusLine() throws {
        let records = try FixtureFiles.load().filter { $0.file == "provider_errors.jsonl" }
        var state = TranscriptState(liveSessionID: "961548ca")
        var sawRetryLine = false
        for record in records {
            guard case .event(let envelope) = record.frame else { continue }
            state.apply(.event(envelope, replayed: false))
            if state.turn?.statusLine?.contains("retrying automatically") == true { sawRetryLine = true }
        }
        XCTAssertTrue(sawRetryLine)
        XCTAssertNil(state.reclaimed, "reclaims of other sessions are ignored")
    }

    func testColdResumeContinuesInflightTextOnce() throws {
        let replay = try FixtureTranscripts.replay("cold_resume_inflight.jsonl")
        let state = try XCTUnwrap(replay.sessions["29bb3931"])
        XCTAssertEqual(state.shape, ["user", "assistant"])
        XCTAssertEqual(state.userEntries.count, 1, "inflight.user matches the stored row, so it is not added twice")
        let final = try XCTUnwrap(replay.completions["29bb3931"]?.last?.text)
        XCTAssertEqual(state.assistantEntries.last?.text, final)
    }

    func testDropAndCatchUpFillsTheGap() throws {
        let replay = try FixtureTranscripts.replay("drop_and_catch_up.jsonl")
        let state = try XCTUnwrap(replay.sessions["397b192c"])
        let final = try XCTUnwrap(replay.completions["397b192c"]?.last?.text)
        XCTAssertEqual(state.assistantEntries.map(\.text), [final])
    }

    func testTruncatedCatchUpAsksForHistory() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("catch_up_truncated.jsonl").sessions["5dcfed87"])
        XCTAssertTrue(state.needsHistoryReload || state.lastSeq != nil)
    }

    func testRewindRemovesTheCutTurns() throws {
        let state = try XCTUnwrap(FixtureTranscripts.replay("rewind.jsonl").sessions["3a8016f6"])
        let sent = state.userEntries.filter { $0.delivery == .sent }
        XCTAssertEqual(sent.map(\.text), ["turn 0 [[scenario:text]]", "edited [[scenario:text]]"])
        XCTAssertEqual(sent.map(\.rowID), [159, 165])
        XCTAssertEqual(
            state.userEntries.count, 2, "the refused edits sat after the cut, so the accepted edit removes them")
        XCTAssertEqual(state.shape, ["user", "assistant", "user", "assistant"])
    }
}
