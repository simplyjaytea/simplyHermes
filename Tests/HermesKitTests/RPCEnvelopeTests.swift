import Foundation
import Testing

@testable import HermesKit

// MARK: - JSONValue

@Test func jsonValueRoundTripsEveryShape() throws {
    let value: JSONValue = [
        "null": nil, "bool": true, "int": 42, "double": 0.5, "string": "x", "array": [1, "two", false],
        "object": ["k": "v"],
    ]
    let data = try JSONEncoder().encode(value)
    let back = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(back == value)
    #expect(back["int"] == .int(42))
    #expect(back["double"] == .double(0.5))
    #expect(back["array"]?[1] == "two")
    #expect(back["array"]?[9] == nil)
    #expect(back["missing"] == nil)
    #expect(back["int"]?.doubleValue == 42)
    #expect(back["null"] == JSONValue.null)
}

@Test func jsonValueDecodesNumbersByShape() throws {
    let decoded = try JSONDecoder().decode(JSONValue.self, from: Data("[1, 1.5, -2, true, null, \"s\"]".utf8))
    #expect(decoded == [1, 1.5, -2, true, nil, "s"])
    #expect(decoded[1] == .double(1.5))
    #expect(decoded[0]?.intValue == 1)
}

@Test func jsonValueLiteralsAndAccessors() {
    let literal: JSONValue = ["a": [true, nil, 2.5, "s"]]
    #expect(literal["a"] == .array([.bool(true), .null, .double(2.5), .string("s")]))
    #expect(literal["a"]?.arrayValue?.count == 4)
    #expect(literal.objectValue?.keys.contains("a") == true)
    #expect(JSONValue.string("x").stringValue == "x")
    #expect(JSONValue.bool(false).boolValue == false)
    #expect(JSONValue.int(1).stringValue == nil)
}

@Test func jsonValueConvertsToAndFromTypedValues() throws {
    let params = ApprovalRespondParams(sessionID: "s1", choice: .session, requestID: "r1")
    let json = try JSONValue(encoding: params)
    #expect(json == ["session_id": "s1", "choice": "session", "request_id": "r1"])
    #expect(try json.decode(ApprovalRespondParams.self) == params)
}

// MARK: - JSON-RPC envelopes

@Test func rpcRequestRoundTripsAndOmitsAbsentParams() throws {
    let bare = RPCRequest(id: "A1", method: "ping")
    #expect(try JSONValue(encoding: bare) == ["jsonrpc": "2.0", "id": "A1", "method": "ping"])

    let typed = try RPCRequest(id: 7, method: "session.create", params: SessionCreateParams())
    #expect(try JSONValue(encoding: typed) == ["jsonrpc": "2.0", "id": 7, "method": "session.create", "params": [:]])

    for request in [bare, typed] {
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(RPCRequest.self, from: data) == request)
    }
}

@Test func rpcResponseRoundTripsSuccessAndErrors() throws {
    let responses = [
        RPCResponse(id: "A2", result: ["session_id": "abc"]),
        RPCResponse(id: 3, result: .null),
        RPCResponse(id: "A3", error: RPCError(code: 4018, message: "gone", data: ["user_turn_count": 3])),
        RPCResponse(id: nil, error: RPCError(code: HermesErrorCode.parseError, message: "Parse error")),
    ]
    for response in responses {
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(RPCResponse.self, from: data) == response)
    }
    let parseError = try JSONValue(encoding: responses[3])
    #expect(parseError["id"] == JSONValue.null)
    #expect(parseError["error"]?["code"] == -32700)
}

@Test func methodNotFoundAnswersMinus32601() throws {
    let response = RPCResponse.methodNotFound(id: "srq-9", method: "terminal.read")
    #expect(response.error?.code == HermesErrorCode.methodNotFound)
    #expect(response.error?.message == "unknown method: terminal.read")
    #expect(try JSONValue(encoding: response)["id"] == "srq-9")
}

private func decodeFrame(_ json: String) throws -> RPCFrame {
    try JSONDecoder().decode(RPCFrame.self, from: Data(json.utf8))
}

private func frameKind(_ frame: RPCFrame) -> String {
    switch frame {
    case .request: "request"
    case .response: "response"
    case .event: "event"
    case .notification: "notification"
    }
}

@Test func rpcFrameClassifiesEveryShape() throws {
    let cases: [(json: String, kind: String)] = [
        (#"{"jsonrpc":"2.0","id":"srq-1","method":"approval","params":{"session_id":"s"}}"#, "request"),
        (#"{"jsonrpc":"2.0","id":"A1","result":{"server_requests":[]}}"#, "response"),
        (#"{"jsonrpc":"2.0","id":"A2","error":{"code":4001,"message":"session not found"}}"#, "response"),
        (#"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}"#, "response"),
        (#"{"jsonrpc":"2.0","method":"log.line","params":{"text":"hi"}}"#, "notification"),
        (
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"sessions.changed","session_id":"","payload":{}}}"#,
            "event"
        ),
    ]
    for testCase in cases {
        let frame = try decodeFrame(testCase.json)
        #expect(frameKind(frame) == testCase.kind, "\(testCase.json)")
    }
    let parse = try decodeFrame(cases[3].json)
    #expect(parse.response?.id == nil)
}

@Test func rpcFrameEncodesBackToTheSameShape() throws {
    let envelope = GatewayEventEnvelope(sessionID: "s1", seq: 4, event: .messageDelta(StreamDelta(text: "hi")))
    let frames: [RPCFrame] = [
        .event(envelope),
        .request(try RPCRequest(id: "srq-1", method: "sudo", params: JSONValue.object(["session_id": "s1"]))),
        .response(RPCResponse(id: "A1", result: ["ok": true])),
        .notification(RPCNotification(method: "log.line", params: ["text": "hi"])),
    ]
    for frame in frames {
        let data = try JSONEncoder().encode(frame)
        #expect(try JSONDecoder().decode(RPCFrame.self, from: data) == frame)
    }
    let json = try JSONValue(encoding: frames[0])
    #expect(json["jsonrpc"] == "2.0")
    #expect(json["method"] == "event")
}

@Test func unknownFieldsAreIgnoredEverywhere() throws {
    let frame = try decodeFrame(
        #"{"jsonrpc":"2.0","id":"A1","extra_top":true,"result":{"server_requests":[],"future":{"a":1}}}"#)
    let result = try #require(try frame.response?.decodeResult(ClientCapabilitiesResult.self))
    #expect(result.serverRequests.isEmpty)

    let event = try decodeFrame(
        #"{"jsonrpc":"2.0","method":"event","params":{"type":"status.update","session_id":"s","seq":2,"x":1,"#
            + #""payload":{"kind":"lifecycle","text":"t","new":[]}}}"#
    )
    guard case .event(let envelope) = event else {
        Issue.record("expected an event")
        return
    }
    #expect(envelope.event == .statusUpdate(StatusUpdateEvent(kind: "lifecycle", text: "t")))
}

@Test func malformedFramesThrow() {
    #expect(throws: (any Error).self) { try decodeFrame("not json") }
    #expect(throws: (any Error).self) { try decodeFrame("[]") }
    #expect(throws: (any Error).self) { try decodeFrame(#"{"jsonrpc":"2.0","id":"A1"}"#) }
    #expect(throws: (any Error).self) { try decodeFrame(#"{"jsonrpc":"2.0","method":"event","params":{}}"#) }
}

// MARK: - Rewind params

@Test func promptSubmitTruncateEncodesRowIDWithoutNullKeys() throws {
    let params = PromptSubmitParams(
        sessionID: "s1", text: "again",
        truncate: PromptTruncate(
            truncateBeforeRowID: 161, truncateBeforeUserOrdinal: 1, confirmDeepTruncate: true))
    let data = try JSONEncoder().encode(params)
    let json = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(
        json
            == [
                "session_id": "s1", "text": "again", "truncate_before_row_id": 161,
                "truncate_before_user_ordinal": 1, "confirm_truncate": true, "confirm_deep_truncate": true,
            ])
    #expect(!containsNull(json))
    #expect(try JSONDecoder().decode(PromptSubmitParams.self, from: data) == params)
}

@Test func promptSubmitWithoutTruncateCarriesNoTruncateKeys() throws {
    let params = PromptSubmitParams(sessionID: "s1", text: "hi")
    let json = try JSONValue(encoding: params)
    #expect(json == ["session_id": "s1", "text": "hi"])
    #expect(try JSONDecoder().decode(PromptSubmitParams.self, from: JSONEncoder().encode(params)) == params)
}

private func containsNull(_ value: JSONValue) -> Bool {
    switch value {
    case .null: true
    case .array(let items): items.contains(where: containsNull)
    case .object(let members): members.values.contains(where: containsNull)
    default: false
    }
}

// MARK: - Open enums and error codes

@Test func openEnumsKeepUnknownValues() throws {
    let status = try JSONDecoder().decode(PromptSubmitStatus.self, from: Data(#""someday""#.utf8))
    #expect(status == .unknown("someday"))
    #expect(try JSONValue(encoding: status) == "someday")
    #expect(try JSONDecoder().decode(InterruptStatus.self, from: Data(#""not_interrupted""#.utf8)) == .notInterrupted)
    #expect(try JSONDecoder().decode(ApprovalChoice.self, from: Data(#""never""#.utf8)) == .unknown("never"))
}

@Test func errorCodesMatchTheProtocolDoc() {
    #expect(HermesErrorCode.parseError == -32700)
    #expect(HermesErrorCode.methodNotFound == -32601)
    #expect(HermesErrorCode.internalError == -32603)
    #expect(HermesErrorCode.sessionNotFound == 4001)
    #expect(HermesErrorCode.sessionNotFoundAlternate == 4007)
    #expect(HermesErrorCode.targetTurnMissing == 4018)
    #expect(HermesErrorCode.truncateNeedsConfirmation == 4029)
    #expect(HermesErrorCode.truncateOrdinalMismatch == 4030)
    #expect(HermesErrorCode.roomEventRejected == 4111)
}
