import HermesKit
import Testing

/// Every recorded frame is checked against the models: frames decode, typed events stay typed, server requests decode,
/// and outgoing params and results round-trip through the typed structs.

@Test func everyFixtureFrameDecodesAsRPCFrame() throws {
    // load() throws on the first frame that does not decode as an RPCFrame.
    let records = try FixtureFiles.load()
    #expect(records.count > 100)
    #expect(records.contains { $0.dir == "out" })
    #expect(records.contains { $0.dir == "in" })
}

/// Fixture events that decode to `.unknown`. Keep the list empty if you can: every event type recorded in `Fixtures/`
/// has a typed case. Add a type here only with a reason, such as a new upstream event not yet modelled.
private let unknownEventAllowList: Set<String> = []

@Test func everyFixtureEventDecodesAndOnlyAllowListedTypesAreUnknown() throws {
    var unknownCounts: [String: Int] = [:]
    var typedCounts: [String: Int] = [:]
    var eventCount = 0
    for record in try FixtureFiles.load() where record.dir == "in" {
        guard case .event(let envelope) = record.frame else { continue }
        eventCount += 1
        #expect(envelope.event.typeName == envelope.type, "\(record.file):\(record.line)")
        if case .unknown = envelope.event {
            unknownCounts[envelope.type, default: 0] += 1
        } else {
            typedCounts[envelope.type, default: 0] += 1
        }
    }
    #expect(eventCount > 200)
    #expect(
        Set(unknownCounts.keys) == unknownEventAllowList,
        "event types that fell into .unknown: \(unknownCounts.sorted { $0.key < $1.key })")
    for type in [
        "gateway.ready", "session.info", "session.title", "message.start", "message.delta", "message.interim",
        "message.complete", "reasoning.available", "thinking.delta", "tool.generating", "tool.start",
        "tool.complete", "status.update", "request.cancel", "session.reclaimed", "sessions.changed",
        "subagent.start", "subagent.thinking", "subagent.complete",
    ] {
        #expect((typedCounts[type] ?? 0) > 0, "\(type) never decoded to a typed case")
    }
}

@Test func serverRequestsDecodeToTypedCases() throws {
    var typedCount = 0
    var approvalCount = 0
    for record in try FixtureFiles.load() where record.dir == "in" {
        guard case .request = record.frame else { continue }
        let request = try #require(try ServerRequest(frame: record.frame))
        switch request {
        case .unknown(_, let method, _):
            Issue.record("\(record.file):\(record.line) server request '\(method)' has no typed case")
        case .approval(_, let approval):
            typedCount += 1
            approvalCount += 1
            #expect(approval.choices == [.once, .session, .always, .deny])
            #expect(approval.allowPermanent == true)
        default:
            typedCount += 1
        }
    }
    #expect(typedCount == 5)  // three approval, one clarify, one sudo
    #expect(approvalCount == 3)
}

/// Each client request in the fixtures, decoded into its typed params and encoded again, must give the same JSON.
/// That proves the structs cover every key the client sends, and that nothing is added (no nulls, no defaults).
@Test func outgoingParamsRoundTripThroughTypedModels() throws {
    func roundTrip<Params: Codable>(_ type: Params.Type, _ params: JSONValue?) throws -> JSONValue {
        try JSONValue(encoding: (params ?? .object([:])).decode(type))
    }
    let checks: [String: (JSONValue?) throws -> JSONValue] = [
        "client.capabilities": { try roundTrip(ClientCapabilitiesParams.self, $0) },
        "gateway.capabilities": { try roundTrip(EmptyParams.self, $0) },
        "ping": { try roundTrip(EmptyParams.self, $0) },
        "gateway.ping": { try roundTrip(EmptyParams.self, $0) },
        "session.create": { try roundTrip(SessionCreateParams.self, $0) },
        "session.list": { try roundTrip(SessionListParams.self, $0) },
        "session.active_list": { try roundTrip(SessionActiveListParams.self, $0) },
        "session.activate": { try roundTrip(SessionActivateParams.self, $0) },
        "session.resume": { try roundTrip(SessionResumeParams.self, $0) },
        "session.history": { try roundTrip(SessionHistoryParams.self, $0) },
        "session.status": { try roundTrip(SessionStatusParams.self, $0) },
        "session.usage": { try roundTrip(SessionUsageParams.self, $0) },
        "session.interrupt": { try roundTrip(SessionInterruptParams.self, $0) },
        "session.events.since": { try roundTrip(SessionEventsSinceParams.self, $0) },
        "prompt.submit": { try roundTrip(PromptSubmitParams.self, $0) },
        "approval.respond": { try roundTrip(ApprovalRespondParams.self, $0) },
        "profiles.list": { try roundTrip(ProfilesListParams.self, $0) },
        "profiles.create": { try roundTrip(ProfilesCreateParams.self, $0) },
        "profiles.describe": { try roundTrip(ProfilesDescribeParams.self, $0) },
        "groups.capabilities": { try roundTrip(GroupsCapabilitiesParams.self, $0) },
        "groups.create": { try roundTrip(GroupsCreateParams.self, $0) },
        "groups.send": { try roundTrip(GroupsSendParams.self, $0) },
        "groups.log": { try roundTrip(GroupsLogParams.self, $0) },
        "groups.state": { try roundTrip(GroupsStateParams.self, $0) },
        "groups.stop": { try roundTrip(GroupsStopParams.self, $0) },
        "groups.list": { try roundTrip(GroupsListParams.self, $0) },
        "groups.disband": { try roundTrip(GroupsDisbandParams.self, $0) },
        "model.options": { try roundTrip(ModelOptionsParams.self, $0) },
        "config.get": { try roundTrip(ConfigGetParams.self, $0) },
        "commands.catalog": { try roundTrip(CommandsCatalogParams.self, $0) },
        "subagent.list": { try roundTrip(SubagentListParams.self, $0) },
        "spawn_tree.list": { try roundTrip(SpawnTreeListParams.self, $0) },
    ]
    var checked = 0
    for record in try FixtureFiles.load() where record.dir == "out" {
        guard case .request(let request) = record.frame else { continue }
        guard let check = checks[request.method] else {
            Issue.record("no typed params for \(request.method) (\(record.file):\(record.line))")
            continue
        }
        // Deliberate rewind error frames are checked in `rewindFramesEncodeTheRowIDAndConfirm`.
        if isDeliberateRewindError(request.params) { continue }
        let original = request.params ?? .object([:])
        let encoded = try check(request.params)
        #expect(encoded == original, "\(record.file):\(record.line) \(request.method)")
        checked += 1
    }
    #expect(checked > 60)
}

/// True for the rewind frames the server rejected on purpose: a boolean or ordinal-only cut, or a cut without
/// `confirm_truncate`. This client never sends those shapes.
private func isDeliberateRewindError(_ params: JSONValue?) -> Bool {
    guard let params else { return false }
    let hasRowID = params["truncate_before_row_id"] != nil
    let hasOrdinal = params["truncate_before_user_ordinal"] != nil
    if hasOrdinal && params["truncate_before_user_ordinal"]?.intValue == nil { return true }
    if hasOrdinal && !hasRowID { return true }
    if hasRowID && params["confirm_truncate"]?.boolValue != true { return true }
    return false
}

@Test func rewindFramesEncodeTheRowIDAndConfirm() throws {
    // The fixture's valid deep cut: row 161 with confirm_truncate and confirm_deep_truncate.
    let fixtureParams: JSONValue = [
        "session_id": "3a8016f6", "text": "edited [[scenario:text]]", "truncate_before_row_id": 161,
        "confirm_truncate": true, "confirm_deep_truncate": true,
    ]
    let decoded = try fixtureParams.decode(PromptSubmitParams.self)
    #expect(decoded.truncate == PromptTruncate(truncateBeforeRowID: 161, confirmDeepTruncate: true))
    let reencoded = try JSONValue(encoding: decoded)
    #expect(reencoded == fixtureParams)

    // A cut the client builds without a confirmation flag still carries confirm_truncate: true, and no null keys.
    let built = PromptSubmitParams(
        sessionID: "3a8016f6", text: "edited", truncate: PromptTruncate(truncateBeforeRowID: 163))
    let encoded = try JSONValue(encoding: built)
    #expect(encoded["truncate_before_row_id"] == 163)
    #expect(encoded["confirm_truncate"] == true)
    #expect(encoded["truncate_before_user_ordinal"] == nil)
    #expect(encoded["confirm_deep_truncate"] == nil)
}

@Test func resultsDecodeFromFixtures() throws {
    let decoders: [String: (JSONValue) throws -> Void] = [
        "client.capabilities": { _ = try $0.decode(ClientCapabilitiesResult.self) },
        "gateway.capabilities": { _ = try $0.decode(GatewayCapabilitiesResult.self) },
        "ping": { _ = try $0.decode(PingResult.self) },
        "gateway.ping": { _ = try $0.decode(GatewayPingResult.self) },
        "session.create": { _ = try $0.decode(SessionCreateResult.self) },
        "session.resume": { _ = try $0.decode(SessionResumeResult.self) },
        "session.activate": { _ = try $0.decode(SessionActivateResult.self) },
        "session.list": { _ = try $0.decode(SessionListResult.self) },
        "session.active_list": { _ = try $0.decode(SessionActiveListResult.self) },
        "session.history": { _ = try $0.decode(SessionHistoryResult.self) },
        "session.status": { _ = try $0.decode(SessionStatusResult.self) },
        "session.usage": { _ = try $0.decode(SessionUsageResult.self) },
        "session.interrupt": { _ = try $0.decode(SessionInterruptResult.self) },
        "session.events.since": { _ = try $0.decode(SessionEventsSinceResult.self) },
        "prompt.submit": { _ = try $0.decode(PromptSubmitResult.self) },
        "approval.respond": { _ = try $0.decode(ApprovalRespondResult.self) },
        "profiles.list": { _ = try $0.decode(ProfilesListResult.self) },
        "profiles.describe": { _ = try $0.decode(ProfilesDescribeResult.self) },
        "groups.capabilities": { _ = try $0.decode(GroupsCapabilitiesResult.self) },
        "groups.create": { _ = try $0.decode(GroupsCreateResult.self) },
        "groups.send": { _ = try $0.decode(GroupsSendResult.self) },
        "groups.log": { _ = try $0.decode(GroupsLogResult.self) },
        "groups.state": { _ = try $0.decode(GroupsStateResult.self) },
        "groups.stop": { _ = try $0.decode(GroupsStopResult.self) },
        "groups.list": { _ = try $0.decode(GroupsListResult.self) },
        "groups.disband": { _ = try $0.decode(GroupsDisbandResult.self) },
        "model.options": { _ = try $0.decode(ModelOptionsResult.self) },
        "commands.catalog": { _ = try $0.decode(CommandsCatalogResult.self) },
        "subagent.list": { _ = try $0.decode(SubagentListResult.self) },
        "spawn_tree.list": { _ = try $0.decode(SpawnTreeListResult.self) },
    ]
    var decodedCount = 0
    var methods: Set<String> = []
    for record in try FixtureFiles.load() where record.dir == "in" {
        guard case .response(let response) = record.frame, let result = response.result,
            let method = record.method, let decode = decoders[method]
        else { continue }
        try decode(result)
        decodedCount += 1
        methods.insert(method)
    }
    #expect(decodedCount > 40)
    #expect(methods.count >= 30)
}

@Test func keyResultsCarryTheFixtureValues() throws {
    let records = try FixtureFiles.load()

    // session.events.since on an overflowed ring: the gap is reported, and the watermark moves to latest_seq.
    let overflow = try #require(
        records.first {
            $0.file == "catch_up_truncated.jsonl" && $0.dir == "in" && $0.method == "session.events.since"
        })
    let catchUp = try #require(try overflow.frame.response?.decodeResult(SessionEventsSinceResult.self))
    #expect(catchUp.truncated)
    #expect(catchUp.latestSeq == 1006)
    #expect(catchUp.count == 512)
    #expect(catchUp.events.count == 512)

    // Rewind: the valid deep cut reports the surviving row ids and the row of the new user message.
    let cut = try #require(
        records.lazy.compactMap { record -> PromptSubmitResult? in
            guard record.file == "rewind.jsonl", record.method == "prompt.submit" else { return nil }
            return try? record.frame.response?.decodeResult(PromptSubmitResult.self)
        }.first { $0.survivorUserRowIDs != nil })
    #expect(cut.status == .streaming)
    #expect(cut.survivorUserRowIDs == [159])
    #expect(cut.userRowID == 165)

    // message.complete carries the durable row ids that rewind caches.
    let complete = try #require(
        records.lazy.compactMap { record -> MessageCompleteEvent? in
            guard record.file == "approval.jsonl", case .event(let envelope) = record.frame,
                case .messageComplete(let payload) = envelope.event
            else { return nil }
            return payload
        }.first)
    #expect(complete.text == "Approval flow finished.")
    #expect(complete.status == .complete)
    #expect(complete.persistedTurn?.rowIDs == [131, 132, 133, 134])
    #expect(complete.usage?.model == "fake-model")

    let interrupt = try #require(
        records.first { $0.file == "interrupt.jsonl" && $0.dir == "in" && $0.method == "session.interrupt" })
    let interrupted = try #require(try interrupt.frame.response?.decodeResult(SessionInterruptResult.self))
    #expect(interrupted.status == .interrupted)
}
