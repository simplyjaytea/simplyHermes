import Foundation
import Testing

@testable import HermesKit

private final class FakeChatTransport: ChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let attachResult: SessionAttachResult
    private var continuation: AsyncStream<GatewayClientEvent>.Continuation?
    private(set) var submitted: [PromptSubmitParams] = []
    private(set) var interrupts = 0
    private(set) var steered: [String] = []
    private(set) var uploads: [String] = []
    var failSubmit: RPCError?
    /// Runs inside `prompt.submit`, before it answers. Tests use it to deliver events ahead of the answer.
    var duringSubmit: (@Sendable () async throws -> Void)?
    /// What `session.history` answers with. `session.undo` takes rows out of it, as the server does.
    var storedHistory: [JSONValue]
    private(set) var undoCalls = 0
    /// Makes the n-th `session.undo` call (counting from 1) fail.
    var failUndoOnCall: Int?
    /// Makes `session.undo` answer without taking anything, as a server that ignored it would.
    var undoTakesNothing = false
    /// Runs inside `session.undo`, before it answers. Tests use it to deliver events during a rewind.
    var duringUndo: (@Sendable () async throws -> Void)?
    var refuseImages = false
    var fileReference = "@file:notes.txt"

    init(history: [JSONValue] = []) throws {
        let object: JSONValue = [
            "session_id": "abcd1234", "message_count": .int(history.count), "messages": .array(history),
            "info": ["model": "m"], "stored_session_id": "20261015_000000_aaaaaa",
        ]
        attachResult = try object.decode(SessionAttachResult.self)
        storedHistory = history
    }

    func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult { attachResult }

    func clientEvents() async -> AsyncStream<GatewayClientEvent> {
        let (stream, continuation) = AsyncStream<GatewayClientEvent>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult {
        lock.withLock { submitted.append(params) }
        try await duringSubmit?()
        if let failSubmit { throw failSubmit }
        return try JSONDecoder().decode(
            PromptSubmitResult.self, from: Data(#"{"status":"streaming","user_row_id":9}"#.utf8))
    }

    func steerSession(_ params: SessionSteerParams) async throws { lock.withLock { steered.append(params.text) } }

    func interruptSession(_ params: SessionInterruptParams) async throws { lock.withLock { interrupts += 1 } }

    func attachImage(_ params: ImageAttachBytesParams) async throws -> AttachedImageResult {
        lock.withLock { uploads.append("image:\(params.filename ?? "")") }
        return AttachedImageResult(attached: !refuseImages, message: refuseImages ? "too large" : nil)
    }

    func attachPDF(_ params: PdfAttachParams) async throws -> PdfAttachResult {
        lock.withLock { uploads.append("pdf:\(params.filename ?? "")") }
        return PdfAttachResult(attached: true, pagesAttached: 2)
    }

    func attachFile(_ params: FileAttachParams) async throws -> FileAttachResult {
        lock.withLock { uploads.append("file:\(params.name)") }
        return FileAttachResult(attached: true, name: params.name, refText: fileReference)
    }

    func sessionHistory(_ params: SessionHistoryParams) async throws -> SessionHistoryResult {
        let rows = lock.withLock { storedHistory }
        let object: JSONValue = ["count": .int(rows.count), "messages": .array(rows)]
        return try object.decode(SessionHistoryResult.self)
    }

    /// Drops the last user row and every row after it, as the server does.
    func undoSession(_ params: SessionUndoParams) async throws -> SessionUndoResult {
        try await duringUndo?()
        let step = lock.withLock { () -> Result<Int, RPCError> in
            undoCalls += 1
            if undoCalls == failUndoOnCall { return .failure(RPCError(code: 5000, message: "no undo", data: nil)) }
            guard !undoTakesNothing,
                let last = storedHistory.lastIndex(where: { $0["role"]?.stringValue == "user" })
            else { return .success(0) }
            let removed = storedHistory.count - last
            storedHistory.removeSubrange(last...)
            return .success(removed)
        }
        return SessionUndoResult(removed: try step.get())
    }
}

private func envelope(_ type: String, _ payload: JSONValue, seq: Int) throws -> GatewayClientEvent {
    let object: JSONValue = ["type": .string(type), "session_id": "abcd1234", "payload": payload, "seq": .int(seq)]
    return .event(try object.decode(GatewayEventEnvelope.self), replayed: false)
}

/// Two user turns, each with a reply: row ids 1 to 4.
private let twoTurns: [JSONValue] = [
    ["role": "user", "text": "first", "row_id": 1], ["role": "assistant", "text": "one", "row_id": 2],
    ["role": "user", "text": "second", "row_id": 3], ["role": "assistant", "text": "two", "row_id": 4],
]

/// Three user turns, each with a reply: row ids 1 to 6.
private let threeTurns: [JSONValue] =
    twoTurns + [
        ["role": "user", "text": "third", "row_id": 5], ["role": "assistant", "text": "three", "row_id": 6],
    ]

/// Runs an edit and unwraps the outcome. Nil would mean the controller did nothing, which these tests do not expect.
private func edited(
    _ controller: ChatSessionController, text: String = "new", fromRowID rowID: Int, consent: TurnEditConsent = []
) async throws -> TurnEditOutcome {
    let outcome = await controller.edit(text: text, fromRowID: rowID, consent: consent)
    return try #require(outcome)
}

/// Runs a rewind and unwraps the outcome. Nil would mean the controller did nothing, which these tests do not expect.
private func rewound(
    _ controller: ChatSessionController, toRowID rowID: Int, consent: TurnEditConsent = []
) async throws -> RewindOutcome {
    let outcome = await controller.rewind(toRowID: rowID, consent: consent)
    return try #require(outcome)
}

/// One line per row, such as `user: first`, so a test can compare the whole transcript.
private func lines(_ state: TranscriptState) -> [String] {
    state.items.map { item -> String in
        switch item.content {
        case .user(let entry): "user: \(entry.text)"
        case .assistant(let entry): "assistant: \(entry.text)"
        case .tool(let entry): "tool: \(entry.name)"
        case .other(let role, let text): "\(role): \(text)"
        }
    }
}

@Suite struct ChatSessionControllerTests {
    @Test func attachShowsHistory() async throws {
        let transport = try FakeChatTransport(history: [["role": "user", "text": "hi", "row_id": 1]])
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let state = await controller.current
        #expect(state.liveSessionID == "abcd1234")
        #expect(state.items.count == 1)
    }

    @Test func sendAddsRowAndAcknowledges() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("  hello  ")
        let state = await controller.current
        guard case .user(let entry) = state.items.last?.content else {
            Issue.record("no user row")
            return
        }
        #expect(entry.text == "hello")
        #expect(entry.delivery == .sent)
        #expect(transport.submitted.first?.text == "hello")
    }

    @Test func failedSendMarksRowFailed() async throws {
        let transport = try FakeChatTransport()
        transport.failSubmit = RPCError(code: 5000, message: "boom", data: nil)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("hello")
        let state = await controller.current
        guard case .user(let entry) = state.items.last?.content else {
            Issue.record("no user row")
            return
        }
        #expect(entry.delivery == .failed("boom"))
    }

    @Test func eventsStreamIntoAssistantRow() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        await controller.handle(try envelope("message.delta", ["text": "Hel"], seq: 2))
        await controller.handle(try envelope("message.delta", ["text": "lo"], seq: 3))
        let state = await controller.current
        guard case .assistant(let entry) = state.items.last?.content else {
            Issue.record("no assistant row")
            return
        }
        #expect(entry.text == "Hello")
        #expect(entry.isStreaming)
        #expect(state.turn != nil)
    }

    @Test func stopInterrupts() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.stop()
        #expect(transport.interrupts == 1)
    }

    @Test func messageWhileBusyWaitsThenSendsWhenTurnEnds() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        await controller.send("later")
        #expect(transport.submitted.isEmpty)
        #expect(await controller.pendingMessages.entries.map(\.text) == ["later"])
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.submitted.map(\.text) == ["later"])
        #expect(await controller.pendingMessages.isEmpty)
    }

    @Test func pausedQueueHoldsUntilResumed() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        await controller.send("held")
        await controller.setQueuePaused(true)
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.submitted.isEmpty)
        await controller.setQueuePaused(false)
        #expect(transport.submitted.map(\.text) == ["held"])
    }

    @Test func steerNeedsARunningTurn() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.steer("go left") == false)
        await controller.handle(try envelope("message.start", [:], seq: 1))
        #expect(await controller.steer("go left") == true)
        #expect(transport.steered == ["go left"])
    }

    @Test func retryLastResendsTheLastTypedPrompt() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("first")
        await controller.handle(try envelope("message.start", [:], seq: 1))
        await controller.handle(try envelope("message.complete", ["status": "error", "error": "429"], seq: 2))
        await controller.retryLast()
        #expect(transport.submitted.map(\.text) == ["first", "first"])
    }

    @Test func attachmentsUploadBeforeThePromptCarryingFileReferences() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1, 2]))
        let notes = ComposerAttachment(kind: .file, name: "notes.txt", data: Data("hi".utf8))
        await controller.send("look at these", attachments: [photo, notes])
        #expect(transport.uploads == ["image:IMG_1.jpg", "file:notes.txt"])
        #expect(transport.submitted.map(\.text) == ["look at these\n@file:notes.txt"])
    }

    @Test func attachmentsWithoutTextSendTheirNames() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        await controller.send("", attachments: [photo])
        #expect(transport.submitted.map(\.text) == ["IMG_1.jpg"])
    }

    @Test func refusedAttachmentFailsTheRowWithoutSubmitting() async throws {
        let transport = try FakeChatTransport()
        transport.refuseImages = true
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        await controller.send("look", attachments: [photo])
        #expect(transport.submitted.isEmpty)
        guard case .user(let entry) = (await controller.current).items.last?.content else {
            Issue.record("no user row")
            return
        }
        #expect(entry.delivery == .failed("IMG_1.jpg: too large"))
    }

    @Test func queuedMessageKeepsItsFilesUntilItSends() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        await controller.send("later", attachments: [photo])
        #expect(transport.uploads.isEmpty)
        #expect(await controller.pendingMessages.entries.first?.attachments.map(\.name) == ["IMG_1.jpg"])
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.uploads == ["image:IMG_1.jpg"])
        #expect(transport.submitted.map(\.text) == ["later"])
    }

    @Test func editCutsTheOldTurnAndKeepsTheReplyBelowTheEditedMessage() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        // The server starts the new turn before its answer reaches the app.
        transport.duringSubmit = {
            await controller.handle(try envelope("message.start", [:], seq: 1))
            await controller.handle(try envelope("message.delta", ["text": "Hi"], seq: 2))
        }
        let outcome = try await edited(controller, fromRowID: 3)
        guard case .done = outcome else {
            Issue.record("expected done, got \(outcome)")
            return
        }
        #expect(transport.submitted.first?.truncate?.truncateBeforeRowID == 3)
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one", "user: new", "assistant: Hi"])
        #expect(state.userEntries.last?.rowID == 9)
        #expect(state.userEntries.last?.delivery == .sent)
        #expect(state.turn != nil)
    }

    @Test func editThatNeedsAYesChangesNothingUntilItGetsOne() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let first = try await edited(controller, fromRowID: 1)
        guard case .needsConfirmation(let question) = first else {
            Issue.record("expected a question, got \(first)")
            return
        }
        #expect(question == .emptiesTranscript)
        #expect(transport.submitted.isEmpty)
        let untouched = await controller.current
        #expect(lines(untouched).count == 4)
        // One yes to this question is enough: it also covers the deep cut, so the question does not come back.
        let second = try await edited(controller, fromRowID: 1, consent: question.consent)
        guard case .done = second else {
            Issue.record("expected done, got \(second)")
            return
        }
        #expect(transport.submitted.count == 1)
        #expect(transport.submitted.first?.truncate?.confirmEmptyTruncate == true)
        #expect(transport.submitted.first?.truncate?.confirmDeepTruncate == true)
        let cut = await controller.current
        #expect(lines(cut) == ["user: new"])
    }

    @Test func refusedEditChangesNothingAndFreesTheChat() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        transport.failSubmit = RPCError(code: 5000, message: "boom", data: nil)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let outcome = try await edited(controller, fromRowID: 3)
        guard case .failed(let error) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(error.message == "boom")
        let untouched = await controller.current
        #expect(lines(untouched) == ["user: first", "assistant: one", "user: second", "assistant: two"])
        // The chat is free again: a new message goes out at once and does not wait in the queue.
        transport.failSubmit = nil
        await controller.send("again")
        #expect(transport.submitted.map(\.text) == ["new", "again"])
        #expect(await controller.pendingMessages.isEmpty)
    }

    @Test func staleRowReadsTheHistoryAgain() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let gone: JSONValue = .object(["user_turn_count": .int(1)])
        transport.failSubmit = RPCError(code: HermesErrorCode.targetTurnMissing, message: "gone", data: gone)
        transport.storedHistory = [["role": "user", "text": "only", "row_id": 5]]
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let outcome = try await edited(controller, fromRowID: 3)
        #expect(outcome == .stale(userTurnCount: 1))
        let reloaded = await controller.current
        #expect(lines(reloaded) == ["user: only"])
    }

    @Test func editNeedsAnAttachedSession() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        #expect(await controller.edit(text: "new", fromRowID: 3) == nil)
        #expect(transport.submitted.isEmpty)
    }
}

@Suite struct ChatSessionRewindTests {
    @Test func rewindAsksFirstThenCutsOneTurnAtATime() async throws {
        let transport = try FakeChatTransport(history: threeTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let first = try await rewound(controller, toRowID: 3)
        guard case .needsConfirmation(let question) = first else {
            Issue.record("expected a question, got \(first)")
            return
        }
        #expect(question == .deepCut(archivedMessages: 4, archivedUserTurns: 2))
        #expect(transport.undoCalls == 0)
        let second = try await rewound(controller, toRowID: 3, consent: question.consent)
        #expect(second == .done(text: "second"))
        #expect(transport.undoCalls == 2)
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one"])
    }

    @Test func rewindOfTheLastTurnNeedsNoQuestion() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(try await rewound(controller, toRowID: 3) == .done(text: "second"))
        #expect(transport.undoCalls == 1)
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one"])
    }

    @Test func rewindOfTheFirstMessageAsksBeforeErasingTheChat() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let first = try await rewound(controller, toRowID: 1)
        guard case .needsConfirmation(let question) = first else {
            Issue.record("expected a question, got \(first)")
            return
        }
        #expect(question == .emptiesTranscript)
        #expect(transport.undoCalls == 0)
        // One yes covers the deep cut too, so the question does not come back.
        let second = try await rewound(controller, toRowID: 1, consent: question.consent)
        #expect(second == .done(text: "first"))
        #expect(transport.undoCalls == 2)
        let state = await controller.current
        #expect(lines(state).isEmpty)
    }

    @Test func tappingARewoundMessageAgainCutsNothingMore() async throws {
        let transport = try FakeChatTransport(history: threeTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(try await rewound(controller, toRowID: 3, consent: .deepCut) == .done(text: "second"))
        #expect(transport.undoCalls == 2)
        // The row is gone from the screen and from the server. A late second tap must not reach the turn before it.
        #expect(try await rewound(controller, toRowID: 3, consent: .deepCut) == .changed)
        #expect(transport.undoCalls == 2)
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one"])
    }

    @Test func aMessageTheServerNeverStoredIsNotCounted() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        transport.failSubmit = RPCError(code: 5000, message: "boom", data: nil)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("lost")
        transport.failSubmit = nil
        // The failed message is on screen below the second turn, but only the second turn is stored.
        let before = await controller.current
        #expect(lines(before) == ["user: first", "assistant: one", "user: second", "assistant: two", "user: lost"])
        #expect(try await rewound(controller, toRowID: 3, consent: .deepCut) == .done(text: "second"))
        #expect(transport.undoCalls == 1)
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one"])
    }

    @Test func rewindRefusesWhenTheServerHoldsOtherTurnsThanTheScreen() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        // Another client added a third turn after this screen was loaded.
        transport.storedHistory = threeTurns
        #expect(try await rewound(controller, toRowID: 3) == .changed)
        #expect(transport.undoCalls == 0)
        let state = await controller.current
        #expect(lines(state).count == 6)
    }

    @Test func aFailedUndoLeavesTheScreenShowingWhatTheServerKept() async throws {
        let transport = try FakeChatTransport(history: threeTurns)
        transport.failUndoOnCall = 2
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let outcome = try await rewound(controller, toRowID: 3, consent: .deepCut)
        guard case .failed(let error) = outcome else {
            Issue.record("expected failed, got \(outcome)")
            return
        }
        #expect(error.message == "no undo")
        #expect(transport.undoCalls == 2)
        // The first undo went through, so the third turn is gone and the screen says so.
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one", "user: second", "assistant: two"])
    }

    @Test func rewindStopsWhenUndoTakesNothing() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        transport.undoTakesNothing = true
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(try await rewound(controller, toRowID: 3) == .changed)
        #expect(transport.undoCalls == 1)
        let state = await controller.current
        #expect(lines(state).count == 4)
    }

    @Test func rewindWaitsForARunningTurn() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        #expect(try await rewound(controller, toRowID: 3) == .busy)
        #expect(transport.undoCalls == 0)
    }

    @Test func eventsDuringARewindWaitUntilTheHistoryIsShown() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        // A new turn starts on the server while the undo is on its way.
        transport.duringUndo = {
            await controller.handle(try envelope("message.start", [:], seq: 1))
            await controller.handle(try envelope("message.delta", ["text": "Hi"], seq: 2))
        }
        #expect(try await rewound(controller, toRowID: 3) == .done(text: "second"))
        let state = await controller.current
        #expect(lines(state) == ["user: first", "assistant: one", "assistant: Hi"])
        #expect(state.turn != nil)
    }

    @Test func rewindNeedsAnAttachedSession() async throws {
        let transport = try FakeChatTransport(history: twoTurns)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        #expect(await controller.rewind(toRowID: 3) == nil)
        #expect(transport.undoCalls == 0)
    }
}
