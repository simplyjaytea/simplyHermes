import Foundation
import Testing

@testable import HermesKit

private final class FakeSession: PromptSession, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [Result<PromptSubmitResult, RPCError>]
    private(set) var submitted: [PromptSubmitParams] = []
    private(set) var interrupts = 0

    init(_ script: [Result<PromptSubmitResult, RPCError>]) { self.script = script }

    func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult {
        let next = lock.withLock { () -> Result<PromptSubmitResult, RPCError>? in
            submitted.append(params)
            return script.isEmpty ? nil : script.removeFirst()
        }
        guard let next else { return try PromptSubmitResult.empty() }
        return try next.get()
    }

    func interruptSession(_ params: SessionInterruptParams) async throws {
        lock.withLock { interrupts += 1 }
    }
}

extension PromptSubmitResult {
    fileprivate static func empty() throws -> PromptSubmitResult {
        try JSONDecoder().decode(PromptSubmitResult.self, from: Data(#"{"status":"streaming","user_row_id":9}"#.utf8))
    }
}

private func failure(_ code: Int, data: JSONValue? = nil) -> Result<PromptSubmitResult, RPCError> {
    .failure(RPCError(code: code, message: "error \(code)", data: data))
}

private func editor(_ session: FakeSession) -> TurnEditor {
    TurnEditor(session: session, sessionID: "live1", profile: "ops")
}

private func user(_ text: String, row: Int, kind: String? = nil) -> TranscriptItem {
    TranscriptItem(
        id: "row-\(row)",
        content: .user(UserEntry(text: text, rowID: row, delivery: .sent, displayKind: kind)))
}

private func assistant(_ text: String, row: Int) -> TranscriptItem {
    TranscriptItem(
        id: "row-\(row)",
        content: .assistant(AssistantEntry(text: text, isStreaming: false, rowID: row)))
}

private func state(_ items: [TranscriptItem]) -> TranscriptState {
    var state = TranscriptState(liveSessionID: "live1")
    state.items = items
    return state
}

@Suite struct TurnEditorTests {
    @Test func successSendsRowIdAndConfirmAndReturnsSurvivors() async throws {
        let result = try JSONDecoder().decode(
            PromptSubmitResult.self,
            from: Data(#"{"status":"streaming","user_row_id":9,"survivor_user_row_ids":[1,3]}"#.utf8))
        let session = FakeSession([.success(result)])
        let outcome = await editor(session).edit(text: "new", fromRowID: 5)
        #expect(outcome == .done(result))
        let sent = try #require(session.submitted.first)
        #expect(sent.truncate?.truncateBeforeRowID == 5)
        #expect(sent.truncate?.truncateBeforeUserOrdinal == nil, "an ordinal alone is refused; never sent")
        #expect(sent.profile == "ops")
        let json = try JSONValue(encoding: sent)
        #expect(json["confirm_truncate"] == .bool(true))
    }

    @Test func serverEmptyCutAsksThenResendsWithConfirm() async throws {
        let session = FakeSession([failure(HermesErrorCode.truncateWouldEmptyTranscript)])
        #expect(await editor(session).edit(text: "x", fromRowID: 1) == .needsConfirmation(.emptiesTranscript))
        let again = await editor(session).edit(text: "x", fromRowID: 1, consent: .emptiesTranscript)
        guard case .done = again else {
            Issue.record("expected done, got \(again)")
            return
        }
        #expect(session.submitted.last?.truncate?.confirmEmptyTruncate == true)
    }

    @Test func serverDeepCutReportsArchivedCounts() async {
        let data: JSONValue = .object(["archived_messages": .int(14), "archived_user_turns": .int(3)])
        let session = FakeSession([failure(HermesErrorCode.deepTruncateUnconfirmed, data: data)])
        let outcome = await editor(session).edit(text: "x", fromRowID: 5)
        #expect(outcome == .needsConfirmation(.deepCut(archivedMessages: 14, archivedUserTurns: 3)))
    }

    @Test func staleRowHasNoFallback() async {
        let data: JSONValue = .object(["user_turn_count": .int(4)])
        let session = FakeSession([failure(HermesErrorCode.targetTurnMissing, data: data)])
        let outcome = await editor(session).edit(text: "x", fromRowID: 5)
        #expect(outcome == .stale(userTurnCount: 4))
        #expect(session.submitted.count == 1, "no retry on 4018")
    }

    @Test func busyInterruptsOnceThenRetries() async {
        let session = FakeSession([failure(HermesErrorCode.sessionBusy)])
        let outcome = await editor(session).edit(text: "x", fromRowID: 5)
        guard case .done = outcome else {
            Issue.record("expected done, got \(outcome)")
            return
        }
        #expect(session.interrupts == 1 && session.submitted.count == 2)
    }

    @Test func busyAfterInterruptGivesUp() async {
        let session = FakeSession([failure(HermesErrorCode.sessionBusy), failure(HermesErrorCode.sessionBusy)])
        #expect(await editor(session).edit(text: "x", fromRowID: 5) == .busy)
        #expect(session.interrupts == 1)
    }

    @Test(arguments: [
        HermesErrorCode.invalidArgument, HermesErrorCode.truncateNeedsConfirmation,
        HermesErrorCode.truncateOrdinalMismatch, HermesErrorCode.internalError,
    ])
    func otherErrorsFailWithoutRetry(code: Int) async {
        let session = FakeSession([failure(code)])
        let outcome = await editor(session).edit(text: "x", fromRowID: 5)
        guard case .failed(let error) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(error.code == code)
        #expect(session.submitted.count == 1)
    }

    @Test func deepCutIsAskedBeforeAnyRequest() async {
        let items = [
            user("a", row: 1), assistant("b", row: 2), user("c", row: 3), assistant("d", row: 4), user("e", row: 5),
        ]
        let impact = RewindImpact.of(state(items), fromRowID: 3)
        #expect(impact == RewindImpact(archivedItems: 3, archivedUserTurns: 2, emptiesTranscript: false))
        let session = FakeSession([])
        let outcome = await editor(session).edit(text: "x", fromRowID: 3, impact: impact)
        #expect(outcome == .needsConfirmation(.deepCut(archivedMessages: 3, archivedUserTurns: 2)))
        #expect(session.submitted.isEmpty)
        _ = await editor(session).edit(text: "x", fromRowID: 3, impact: impact, consent: .deepCut)
        #expect(session.submitted.first?.truncate?.confirmDeepTruncate == true)
    }

    @Test func emptyingCutIsAskedBeforeAnyRequest() async {
        let impact = RewindImpact.of(state([user("a", row: 1), assistant("b", row: 2)]), fromRowID: 1)
        #expect(impact?.emptiesTranscript == true)
        let session = FakeSession([])
        #expect(
            await editor(session).edit(text: "x", fromRowID: 1, impact: impact)
                == .needsConfirmation(.emptiesTranscript))
        #expect(session.submitted.isEmpty)
    }

    @Test func yesToTheEmptyingQuestionAlsoCoversTheDeepCut() async throws {
        // The first message of a chat with two turns is an emptying cut and a deep cut at once.
        let items = [user("a", row: 1), assistant("b", row: 2), user("c", row: 3), assistant("d", row: 4)]
        let impact = RewindImpact.of(state(items), fromRowID: 1)
        #expect(impact == RewindImpact(archivedItems: 4, archivedUserTurns: 2, emptiesTranscript: true))
        let session = FakeSession([])
        let first = await editor(session).edit(text: "x", fromRowID: 1, impact: impact)
        guard case .needsConfirmation(let confirmation) = first else {
            Issue.record("expected a question, got \(first)")
            return
        }
        #expect(confirmation == .emptiesTranscript)
        let second = await editor(session).edit(text: "x", fromRowID: 1, impact: impact, consent: confirmation.consent)
        guard case .done = second else {
            Issue.record("a second question would never end, got \(second)")
            return
        }
        let json = try JSONValue(encoding: try #require(session.submitted.first))
        #expect(json["confirm_empty_truncate"] == .bool(true))
        #expect(json["confirm_deep_truncate"] == .bool(true))
    }

    @Test func yesToTheDeepCutQuestionDoesNotCoverErasingTheChat() {
        let deep = TurnEditConfirmation.deepCut(archivedMessages: 4, archivedUserTurns: 2)
        #expect(deep.consent == .deepCut)
        #expect(TurnEditConfirmation.emptiesTranscript.consent == [.emptiesTranscript, .deepCut])
    }

    @Test func impactIgnoresGatewayStartedTurnsAndUnknownRows() {
        let items = [user("a", row: 1), user("cron", row: 2, kind: "cron"), assistant("b", row: 3)]
        #expect(RewindImpact.of(state(items), fromRowID: 2)?.archivedUserTurns == 0)
        #expect(RewindImpact.of(state(items), fromRowID: 99) == nil)
    }

    @Test func regenerateEditsTheLastStoredUserTurnWithItsOwnText() async {
        let items = [user("first", row: 1), assistant("r", row: 2), user("second", row: 3), assistant("r2", row: 4)]
        let session = FakeSession([])
        let outcome = await editor(session).regenerate(state: state(items))
        guard case .done = outcome else {
            Issue.record("expected done, got \(String(describing: outcome))")
            return
        }
        #expect(session.submitted.first?.text == "second")
        #expect(session.submitted.first?.truncate?.truncateBeforeRowID == 3)
        #expect(await editor(session).regenerate(state: state([])) == nil)
    }

    @Test func branchParamsEncodeWireKeysAndAnIdempotencyKey() throws {
        let json = try JSONValue(encoding: SessionBranchParams(sessionID: "live1", name: "try B", count: 6))
        #expect(json["session_id"] == .string("live1") && json["name"] == .string("try B") && json["count"] == .int(6))
        #expect(json["idempotency_key"]?.stringValue?.isEmpty == false)
        #expect(json["profile"] == nil)
    }
}

@Suite struct RewindTests {
    @Test func localRowsAskForWhatIsStillMissing() {
        let items = [user("a", row: 1), assistant("b", row: 2), user("c", row: 3), assistant("d", row: 4)]
        let everything = RewindImpact.of(state(items), fromRowID: 1)
        #expect(TurnEditor.confirmation(for: everything, consent: []) == .emptiesTranscript)
        #expect(
            TurnEditor.confirmation(for: everything, consent: .emptiesTranscript)
                == .deepCut(archivedMessages: 4, archivedUserTurns: 2))
        #expect(TurnEditor.confirmation(for: everything, consent: [.emptiesTranscript, .deepCut]) == nil)
        let lastTurn = RewindImpact.of(state(items), fromRowID: 3)
        #expect(TurnEditor.confirmation(for: lastTurn, consent: []) == nil)
        #expect(TurnEditor.confirmation(for: nil, consent: []) == nil, "without local rows only the server can ask")
    }

    @Test func userRowsFromATurnOnLeaveOutMessagesTheServerNeverStored() {
        let lost = TranscriptItem(id: "local-1", content: .user(UserEntry(text: "lost", delivery: .failed("boom"))))
        let items = [user("a", row: 1), assistant("b", row: 2), user("c", row: 3), assistant("d", row: 4), lost]
        #expect(RewindImpact.userRowIDs(in: items, from: 1) == [1, 3])
        #expect(RewindImpact.userRowIDs(in: items, from: 3) == [3])
        #expect(RewindImpact.userRowIDs(in: items, from: 2) == nil, "a reply is not a turn to cut at")
        #expect(RewindImpact.userRowIDs(in: items, from: 99) == nil)
    }

    @Test func serverAndScreenAgreeOnlyOnTheSameTurnsFromTheRowOn() {
        let screen = [user("a", row: 1), assistant("b", row: 2), user("c", row: 3), assistant("d", row: 4)]
        let longer = screen + [user("e", row: 5), assistant("f", row: 6)]
        let edited = [user("a", row: 1), assistant("b", row: 2), user("c2", row: 7), assistant("d2", row: 8)]
        let older = [user("z", row: 9), assistant("y", row: 10), user("c", row: 3), assistant("d", row: 4)]
        #expect(RewindImpact.agree(screen, screen, from: 3))
        #expect(RewindImpact.agree(older, screen, from: 3), "a cut at row 3 never reaches the turns before it")
        #expect(!RewindImpact.agree(longer, screen, from: 3), "the server holds a turn the screen lacks")
        #expect(!RewindImpact.agree(screen, longer, from: 3), "the screen shows a turn the server lacks")
        #expect(!RewindImpact.agree(edited, screen, from: 3), "the server no longer holds the row")
        #expect(!RewindImpact.agree(edited, edited, from: 3), "neither side holds the row")
    }

    @Test func undoParamsEncodeWireKeysAndTheResultDecodes() throws {
        let scoped = try JSONValue(encoding: SessionUndoParams(sessionID: "live1", profile: "ops"))
        #expect(scoped["session_id"] == .string("live1") && scoped["profile"] == .string("ops"))
        let plain = try JSONValue(encoding: SessionUndoParams(sessionID: "live1"))
        #expect(plain["profile"] == nil)
        let result = try JSONDecoder().decode(SessionUndoResult.self, from: Data(#"{"removed":3}"#.utf8))
        #expect(result.removed == 3)
    }
}
