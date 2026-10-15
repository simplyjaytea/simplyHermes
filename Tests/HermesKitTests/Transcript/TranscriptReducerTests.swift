import HermesKit
import XCTest

/// Cases the recorded fixtures do not cover: cron turns with `display_kind`, coalescing, duplicates, reclaim.
final class TranscriptReducerTests: XCTestCase {
    private let live = "abcd1234"
    private var seq = 0

    private func event(_ type: String, _ payload: JSONValue = [:], session: String? = nil) throws -> TranscriptAction {
        seq += 1
        let object: JSONValue = [
            "type": .string(type), "session_id": .string(session ?? live), "payload": payload, "seq": .int(seq),
        ]
        return .event(try object.decode(GatewayEventEnvelope.self), replayed: false)
    }

    private func attach(_ fields: JSONValue) throws -> TranscriptAction {
        var object: [String: JSONValue] = [
            "session_id": .string(live), "message_count": 0, "messages": [], "info": ["model": "m"],
            "stored_session_id": "20261015_000000_aaaaaa",
        ]
        for (key, value) in fields.objectValue ?? [:] { object[key] = value }
        return .attached(try JSONValue.object(object).decode(SessionAttachResult.self))
    }

    func testCronInflightKeepsDisplayKind() throws {
        var state = TranscriptState()
        state.apply(
            try attach([
                "running": true,
                "inflight": [
                    "user": "Daily summary", "assistant": "Here is", "streaming": true, "display_kind": "cron",
                    "display_metadata": ["job_name": "[bot:ana] summary"],
                ],
            ]))
        XCTAssertEqual(state.shape, ["user", "assistant"])
        XCTAssertEqual(state.userEntries.first?.displayKind, "cron")
        XCTAssertEqual(state.userEntries.first?.displayMetadata?["job_name"]?.stringValue, "[bot:ana] summary")
        XCTAssertEqual(state.assistantEntries.first?.displayKind, "cron")
        XCTAssertNotNil(state.turn)
        state.apply(try event("message.delta", ["text": " the summary."]))
        XCTAssertEqual(state.assistantEntries.map(\.text), ["Here is the summary."])
        state.apply(try event("message.complete", ["text": "Here is the summary.", "status": "complete"]))
        XCTAssertNil(state.turn)
        XCTAssertEqual(state.assistantEntries.first?.isStreaming, false)
    }

    func testHistoryRowsKeepDisplayKindAndRoles() throws {
        var state = TranscriptState(liveSessionID: live)
        let rows: JSONValue = [
            ["role": "user", "text": "ping", "row_id": 1, "display_kind": "delegation"],
            ["role": "tool", "text": "ok", "tool_call_id": "c1", "row_id": 2, "name": "terminal"],
            ["role": "system", "text": "note"],
        ]
        state.apply(.history(try rows.decode([TranscriptMessage].self)))
        XCTAssertEqual(state.shape, ["user", "tool:terminal", "system"])
        XCTAssertEqual(state.items.map(\.id), ["row-1", "row-2", "history-2"])
        XCTAssertEqual(state.userEntries.first?.displayKind, "delegation")
        XCTAssertEqual(state.toolEntries.first?.resultText, "ok")
    }

    func testDuplicateAndForeignEventsAreDropped() throws {
        var state = TranscriptState(liveSessionID: live)
        state.apply(try event("message.start"))
        let first = try event("message.delta", ["text": "a"])
        state.apply(first)
        state.apply(first)
        state.apply(try event("message.delta", ["text": "x"], session: "ffff0000"))
        state.apply(try event("message.delta", ["text": "b"]))
        XCTAssertEqual(state.assistantEntries.map(\.text), ["ab"])
    }

    func testCoalescingMergesDeltaRuns() throws {
        let actions = [
            try event("message.start"), try event("thinking.delta", ["text": "one"]),
            try event("thinking.delta", ["text": "two"]), try event("message.delta", ["text": "He"]),
            try event("message.delta", ["text": "llo"]), try event("reasoning.delta", ["text": "r1"]),
            try event("reasoning.delta", ["text": "r2"]), try event("message.delta", ["text": "!"]),
        ]
        let merged = TranscriptCoalescer.coalesce(actions)
        XCTAssertEqual(merged.count, 5)
        var oneByOne = TranscriptState(liveSessionID: live)
        for action in actions { oneByOne.apply(action) }
        var batched = TranscriptState(liveSessionID: live)
        batched.apply(contentsOf: actions)
        XCTAssertEqual(batched, oneByOne)
        XCTAssertEqual(batched.assistantEntries.first?.text, "Hello!")
        XCTAssertEqual(batched.assistantEntries.first?.reasoning, "r1r2")
        XCTAssertEqual(batched.turn?.spinnerText, "two")
        XCTAssertEqual(batched.lastSeq, 8)
    }

    func testReasoningBeforeTextWaitsForTheSegment() throws {
        var state = TranscriptState(liveSessionID: live)
        state.apply(try event("message.start"))
        state.apply(try event("reasoning.available", ["text": "plan"]))
        state.apply(try event("message.delta", ["text": "Hi"]))
        XCTAssertEqual(state.assistantEntries.first?.reasoning, "plan")
    }

    func testPendingApprovalFromAttachAndApprovalCancelled() throws {
        var state = TranscriptState()
        state.apply(
            try attach([
                "running": true,
                "pending_approval": ["request_id": "r1", "command": "rm x", "choices": ["once", "deny"]],
            ]))
        XCTAssertEqual(state.openRequests.map(\.id), ["approval:r1"])
        XCTAssertEqual(state.openRequests.first?.replayed, true)
        state.apply(
            try event(
                "approval.cancelled",
                [
                    "session_id": .string(live), "stored_session_id": "s", "reason": "interrupt",
                    "cancelled_count": 1, "request_ids": ["r1"],
                ]))
        XCTAssertTrue(state.openRequests.isEmpty)
    }

    func testReplayedOpenRequestReplacesTheSameApproval() throws {
        var state = TranscriptState(liveSessionID: live)
        let params: JSONValue = ["session_id": .string(live), "request_id": "r9", "command": "ls"]
        state.apply(
            .serverRequest(try ServerRequest(request: RPCRequest(id: "srq-1", method: "approval", params: params))))
        let entry: JSONValue = ["id": "srq-2", "method": "approval", "params": params]
        state.apply(.openRequestReplayed(try entry.decode(OpenRequestEntry.self)))
        XCTAssertEqual(state.openRequests.map(\.id), ["srq-2"])
        state.apply(.requestAnswered(id: "srq-2"))
        XCTAssertTrue(state.openRequests.isEmpty)
    }

    func testReclaimEndsTheTurnAndOtherSessionsAreIgnored() throws {
        var state = TranscriptState(liveSessionID: live)
        state.apply(try event("message.start"))
        let other: JSONValue = ["session_id": "ffff0000", "stored_session_id": "s", "reason": "ws_orphan_reap"]
        state.apply(try event("session.reclaimed", other, session: ""))
        XCTAssertNil(state.reclaimed)
        let mine: JSONValue = ["session_id": .string(live), "stored_session_id": "s", "reason": "ws_orphan_reap"]
        state.apply(try event("session.reclaimed", mine, session: ""))
        XCTAssertEqual(state.reclaimed?.reason, "ws_orphan_reap")
        XCTAssertNil(state.turn)
    }

    func testQueuedSubmitAndOutputRisk() throws {
        var state = TranscriptState(liveSessionID: live)
        state.apply(.userSubmitted(localID: "L1", text: "next"))
        XCTAssertEqual(state.userEntries.first?.delivery, .sending)
        let queued: JSONValue = ["status": "queued"]
        state.apply(.submitAcknowledged(localID: "L1", try queued.decode()))
        XCTAssertEqual(state.userEntries.first?.delivery, .queued)
        state.apply(try event("message.start"))
        state.apply(try event("tool.start", ["tool_id": "t1", "name": "web_extract"]))
        state.apply(
            try event(
                "tool.output_risk",
                [
                    "tool_id": "t1", "name": "web_extract", "risk": "prompt_injection", "findings": ["x"],
                    "redacted": true,
                ]
            ))
        XCTAssertEqual(state.toolEntries.first?.risk?.redacted, true)
        state.apply(try event("error", ["message": "boom"]))
        XCTAssertEqual(state.lastError, "boom")
        XCTAssertNil(state.turn)
    }

    func testClientEventMapping() throws {
        let raw: JSONValue = ["session_id": "abcd1234", "message_count": 0, "messages": [], "info": [:]]
        let result = try raw.decode(SessionAttachResult.self)
        XCTAssertNil(TranscriptAction(.sessionReattached(oldLiveID: "x", result: result, how: .live)))
        XCTAssertEqual(
            TranscriptAction(.sessionReattached(oldLiveID: "x", result: result, how: .cold)), .attached(result))
        XCTAssertEqual(
            TranscriptAction(.replayTruncated(sessionID: "x", latestSeq: 9)), .replayTruncated(latestSeq: 9))
        XCTAssertNil(TranscriptAction(.serverRestarted))
    }
}
