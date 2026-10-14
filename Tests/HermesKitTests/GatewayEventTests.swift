import Foundation
import Testing

@testable import HermesKit

private func decodeEnvelope(_ json: String) throws -> GatewayEventEnvelope {
    try JSONDecoder().decode(GatewayEventEnvelope.self, from: Data(json.utf8))
}

@Test func unknownEventTypeKeepsItsPayload() throws {
    let frame = try JSONDecoder().decode(
        RPCFrame.self,
        from: Data(
            (#"{"jsonrpc":"2.0","method":"event","params":{"type":"made.up.event","session_id":"abc123","#
                + #""payload":{"n":1,"nested":{"xs":[1,"two",null]}},"seq":7}}"#).utf8))
    guard case .event(let envelope) = frame else {
        Issue.record("expected an event frame")
        return
    }
    #expect(envelope.type == "made.up.event")
    #expect(envelope.sessionID == "abc123")
    #expect(envelope.seq == 7)
    let payload: JSONValue = ["n": 1, "nested": ["xs": [1, "two", nil]]]
    #expect(envelope.event == .unknown(type: "made.up.event", payload: payload))
}

@Test func typedEventWithBadPayloadFallsBackToUnknown() throws {
    // message.delta needs a string text: a number must not throw.
    let delta = try decodeEnvelope(#"{"type":"message.delta","session_id":"s","payload":{"text":5},"seq":3}"#)
    #expect(delta.event == .unknown(type: "message.delta", payload: ["text": 5]))

    // message.complete whose usage lacks the required model falls back as a whole.
    let complete = try decodeEnvelope(
        #"{"type":"message.complete","session_id":"s","payload":{"text":"ok","usage":{"input":1}},"seq":4}"#)
    #expect(complete.type == "message.complete")
    if case .unknown(let type, _) = complete.event {
        #expect(type == "message.complete")
    } else {
        Issue.record("message.complete with a broken usage should fall back to .unknown")
    }
}

@Test func eventWithoutPayloadKeepsTheTypedCase() throws {
    let start = try decodeEnvelope(#"{"type":"message.start","session_id":"s","seq":2}"#)
    #expect(start.event == .messageStart)
    #expect(start.sessionID == "s")
    #expect(start.seq == 2)

    // Global events have an empty session id and no seq.
    let changed = try decodeEnvelope(#"{"type":"sessions.changed","session_id":"","payload":{}}"#)
    #expect(changed.event == .sessionsChanged)
    #expect(changed.sessionID == "")
    #expect(changed.seq == nil)

    // An event with no session_id key at all is global too.
    let ready = try decodeEnvelope(
        #"{"type":"gateway.ready","payload":{"skin":{"_trimmed":true},"change_events":true,"heartbeat":true,"replay_epoch":"e1"}}"#
    )
    #expect(ready.sessionID == "")
    #expect(
        ready.event
            == .gatewayReady(
                GatewayReadyEvent(skin: ["_trimmed": true], changeEvents: true, heartbeat: true, replayEpoch: "e1")))
}

@Test func messageCompleteKeepsUsageAndPersistedTurn() throws {
    let envelope = try decodeEnvelope(
        #"""
        {"type":"message.complete","session_id":"s","seq":30,"payload":{"text":"done","status":"complete",
         "usage":{"model":"m","input":200,"output":12,"reasoning":0,"prompt":200,"completion":12,"total":212,
                  "calls":2,"context_percent":0,"context_source":"provider_usage","avg_tps":115.8},
         "persisted_turn":{"row_ids":[131,132],"complete":true,"user_row_id":131,"final_assistant_row_id":132}}}
        """#)
    guard case .messageComplete(let complete) = envelope.event else {
        Issue.record("expected message.complete")
        return
    }
    #expect(complete.status == .complete)
    #expect(complete.usage?.total == 212)
    #expect(complete.usage?.avgTokensPerSecond == 115.8)
    #expect(complete.usage?.contextPercent == 0)
    #expect(
        complete.persistedTurn
            == PersistedTurn(rowIDs: [131, 132], complete: true, userRowID: 131, finalAssistantRowID: 132))
}

@Test func toolEventsKeepLabelsAndRawResults() throws {
    let complete = try decodeEnvelope(
        #"""
        {"type":"tool.complete","session_id":"s","seq":19,"payload":{"tool_id":"call_1","name":"terminal",
         "args":{"command":"ls"},"duration_s":0.25,"result":{"output":"","exit_code":0},
         "labels":[{"kind":"mcp","app":"github","text":"list"},{"kind":"from-the-future"}]}}
        """#)
    guard case .toolComplete(let tool) = complete.event else {
        Issue.record("expected tool.complete")
        return
    }
    #expect(tool.toolID == "call_1")
    #expect(tool.durationSeconds == 0.25)
    #expect(tool.result?["exit_code"] == 0)
    #expect(tool.labels?.first?.kind == .mcp)
    #expect(tool.labels?.last?.kind == .unknown("from-the-future"))
}

@Test func typedEventsRoundTripThroughTheirEnvelope() throws {
    let samples: [GatewayEvent] = [
        .messageStart,
        .messageDelta(StreamDelta(text: "hi")),
        .toolStart(
            ToolStartEvent(
                toolID: "t1", name: "terminal", context: "ls", args: ["command": "ls"], argsText: nil, preview: nil,
                labels: nil)),
        .statusUpdate(StatusUpdateEvent(kind: "lifecycle", text: "retrying")),
        .sessionReclaimed(
            SessionReclaimedEvent(sessionID: "29bb3931", storedSessionID: "2026_x", reason: "ws_orphan_reap")),
        .sessionsChanged,
        .unknown(type: "x.y", payload: ["a": 1]),
    ]
    for event in samples {
        let envelope = GatewayEventEnvelope(sessionID: "s1", seq: 9, event: event)
        let data = try JSONEncoder().encode(envelope)
        let back = try JSONDecoder().decode(GatewayEventEnvelope.self, from: data)
        #expect(back == envelope, "\(event.typeName)")
    }
}

@Test func subagentEventsDecodeTheirTaskFields() throws {
    let envelope = try decodeEnvelope(
        #"""
        {"type":"subagent.complete","session_id":"a3d65ee3","seq":40,"payload":{"goal":"say hello","task_count":1,
         "task_index":0,"subagent_id":"sa-0-094acbf9","status":"completed","tool_count":0,"duration_seconds":1.5,
         "output_tail":[{"tool":"terminal","preview":"ls","is_error":false}]}}
        """#)
    guard case .subagentComplete(let subagent) = envelope.event else {
        Issue.record("expected subagent.complete")
        return
    }
    #expect(subagent.goal == "say hello")
    #expect(subagent.status == .completed)
    #expect(subagent.durationSeconds == 1.5)
    #expect(subagent.outputTail?.count == 1)
}

// MARK: - Server requests

@Test func approvalRequestDecodesAndAnswersEncode() throws {
    let frame = try JSONDecoder().decode(
        RPCFrame.self,
        from: Data(
            #"""
            {"jsonrpc":"2.0","id":"srq-bb333022bf70","method":"approval","params":{"session_id":"6558c086",
             "command":"rm -rf /tmp/x","pattern_key":"delete in root path","pattern_keys":["delete in root path"],
             "description":"delete in root path","allow_permanent":true,"allow_session":true,
             "request_id":"da54646f35fc43e0aea8fef898bc89d0","choices":["once","session","always","deny","never"]}}
            """#.utf8))
    let request = try #require(try ServerRequest(frame: frame))
    guard case .approval(let id, let approval) = request else {
        Issue.record("expected an approval request")
        return
    }
    #expect(id == "srq-bb333022bf70")
    #expect(approval.requestID == "da54646f35fc43e0aea8fef898bc89d0")
    #expect(approval.choices == [.once, .session, .always, .deny, .unknown("never")])
    #expect(request.id == id)
}

@Test func answersEncodeWithoutAbsentKeys() throws {
    #expect(try JSONValue(encoding: ApprovalAnswer(choice: .deny)) == ["choice": "deny"])
    #expect(try JSONValue(encoding: ApprovalAnswer(choice: .once, all: true)) == ["choice": "once", "all": true])
    #expect(try JSONValue(encoding: ClarifyAnswer(answers: ["q0": "staging"])) == ["answers": ["q0": "staging"]])
    #expect(try JSONValue(encoding: ValueAnswer(value: "hunter2")) == ["value": "hunter2"])
}

@Test func clarifyRequestDefaultsMultiSelectToFalse() throws {
    let frame = try JSONDecoder().decode(
        RPCFrame.self,
        from: Data(
            #"""
            {"jsonrpc":"2.0","id":"srq-ac90","method":"clarify","params":{"session_id":"20f3019b","questions":[
             {"qid":"q0","question":"Which target?","choices":["staging (Recommended)","prod"],"multi_select":true},
             {"qid":"q1","question":"Any notes?","choices":null}]}}
            """#.utf8))
    let request = try #require(try ServerRequest(frame: frame))
    guard case .clarify(_, let clarify) = request else {
        Issue.record("expected clarify")
        return
    }
    #expect(clarify.questions[0].multiSelect)
    #expect(!clarify.questions[1].multiSelect)
    #expect(clarify.questions[1].choices == nil)
}

@Test func unmodelledServerRequestsBecomeUnknown() throws {
    let frame = try JSONDecoder().decode(
        RPCFrame.self,
        from: Data(#"{"jsonrpc":"2.0","id":"srq-9","method":"terminal.read","params":{"session_id":"s"}}"#.utf8))
    let request = try #require(try ServerRequest(frame: frame))
    #expect(request == .unknown(id: "srq-9", method: "terminal.read", params: ["session_id": "s"]))
}

@Test func brokenServerRequestParamsThrow() throws {
    let frame = try JSONDecoder().decode(
        RPCFrame.self,
        from: Data(#"{"jsonrpc":"2.0","id":"srq-1","method":"approval","params":{"session_id":5}}"#.utf8))
    #expect(throws: (any Error).self) { try ServerRequest(frame: frame) }
}

@Test func responsesAreNotServerRequests() throws {
    let frame = try JSONDecoder().decode(RPCFrame.self, from: Data(#"{"jsonrpc":"2.0","id":"A1","result":{}}"#.utf8))
    #expect(try ServerRequest(frame: frame) == nil)
}
