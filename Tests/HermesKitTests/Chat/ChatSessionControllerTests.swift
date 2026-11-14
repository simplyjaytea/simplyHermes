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
    /// Fails `prompt.submit` with an error that is not a server refusal, such as a dropped connection.
    var failSubmitError: (any Error)?
    /// Runs inside `prompt.submit`, before it answers. Tests use it to deliver events ahead of the answer.
    var duringSubmit: (@Sendable () async throws -> Void)?
    /// What `session.history` answers with.
    var storedHistory: [JSONValue] = []
    var refuseImages = false
    var fileReference = "@file:notes.txt"
    /// Directive to answer with, by command name. A name with no entry fails, as an unknown command does.
    var dispatchReplies: [String: CommandDispatchResult] = [:]
    private(set) var dispatched: [CommandDispatchParams] = []

    init(history: [JSONValue] = []) throws {
        let object: JSONValue = [
            "session_id": "abcd1234", "message_count": .int(history.count), "messages": .array(history),
            "info": ["model": "m"], "stored_session_id": "20261015_000000_aaaaaa",
        ]
        attachResult = try object.decode(SessionAttachResult.self)
    }

    /// Live ids by stored id, for tests with several chats on this one client. A stored id not listed gets the default.
    var liveIDs: [String: String] = [:]

    func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult {
        if let live = liveIDs[params.sessionID] { return try attach(live: live) }
        return attachResult
    }

    /// The attach result `session.resume` gives for a session whose live id is `live`.
    func attach(live: String) throws -> SessionAttachResult {
        let object: JSONValue = [
            "session_id": .string(live), "message_count": .int(0), "messages": .array([]),
            "info": ["model": "m"], "stored_session_id": "20261015_000000_aaaaaa",
        ]
        return try object.decode(SessionAttachResult.self)
    }

    func clientEvents() async -> AsyncStream<GatewayClientEvent> {
        let (stream, continuation) = AsyncStream<GatewayClientEvent>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult {
        lock.withLock { submitted.append(params) }
        try await duringSubmit?()
        if let failSubmitError { throw failSubmitError }
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
        let object: JSONValue = ["count": .int(storedHistory.count), "messages": .array(storedHistory)]
        return try object.decode(SessionHistoryResult.self)
    }

    func dispatchCommand(_ params: CommandDispatchParams) async throws -> CommandDispatchResult {
        lock.withLock { dispatched.append(params) }
        guard let reply = dispatchReplies[params.name] else {
            throw RPCError(code: 4000, message: "unknown command", data: nil)
        }
        return reply
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

/// Runs an edit and unwraps the outcome. Nil would mean the controller did nothing, which these tests do not expect.
private func edited(
    _ controller: ChatSessionController, text: String = "new", fromRowID rowID: Int, consent: TurnEditConsent = []
) async throws -> TurnEditOutcome {
    let outcome = await controller.edit(text: text, fromRowID: rowID, consent: consent)
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

    /// Regression (Moss, 54b698d): a message sent while Hermes is busy used to wait in a memory queue and report
    /// success, so the composer cleared and the message was lost if the app stopped. Now nothing is held, and nothing
    /// goes out later on its own.
    @Test func messageWhileBusyIsNotSentAndNotHeldInMemory() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        #expect(await controller.send("later") == .notSent)
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.submitted.isEmpty)
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

    /// Regression (Moss, be2cee0): a refused file used to fail its row but report `.sent`, so the composer cleared the
    /// text and the file. The failure now comes back with its reason, and nothing is submitted.
    @Test func aRefusedFileIsReportedSoTheComposerKeepsIt() async throws {
        let transport = try FakeChatTransport()
        transport.refuseImages = true
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        #expect(await controller.send("look", attachments: [photo]) == .failed("IMG_1.jpg: too large"))
        #expect(transport.submitted.isEmpty)
    }

    /// Regression (Moss, be2cee0): a prompt whose submit fails on the network after its files went up is reported as
    /// failed, not sent.
    @Test func aPromptThatFailsOnTheNetworkIsReportedSoTheComposerKeepsIt() async throws {
        let transport = try FakeChatTransport()
        transport.failSubmitError = URLError(.notConnectedToInternet)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        let outcome = await controller.send("look", attachments: [photo])
        #expect(outcome != .sent)
        guard case .failed(let reason) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(transport.uploads == ["image:IMG_1.jpg"])
    }

    /// Regression (Moss, be2cee0): a slash command whose prompt Hermes refuses is reported with Hermes's reason.
    /// After the failure the chat is free, and the next send goes out.
    @Test func aRefusedCommandPromptIsReportedAndTheChatStaysUsable() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["review"] = CommandDispatchResult(type: .send, message: "Review the staged diff")
        transport.failSubmit = RPCError(code: 5000, message: "boom", data: nil)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.send("/review staged") == .failed("boom"))
        transport.failSubmit = nil
        #expect(await controller.send("/review staged") == .sent)
        // The fake records a submit before it fails, so both attempts are listed.
        #expect(transport.submitted.map(\.text) == ["Review the staged diff", "Review the staged diff"])
    }

    /// Regression (Moss, 54b698d): files sent while Hermes is busy are refused, not queued in memory, so the composer
    /// keeps them. Sent again once the turn ends, they go out with the text.
    @Test func filesWhileBusyAreRefusedAndGoOutWhenSentAgain() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        #expect(await controller.send("later", attachments: [photo]) == .notSent)
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.uploads.isEmpty)
        #expect(transport.submitted.isEmpty)
        #expect(await controller.send("later", attachments: [photo]) == .sent)
        #expect(transport.uploads == ["image:IMG_1.jpg"])
        #expect(transport.submitted.map(\.text) == ["later"])
    }

    /// Regression (Moss, 54b698d): a slash command whose prompt cannot go out while Hermes is busy is refused, not
    /// queued. A command that only prints still runs.
    @Test func commandPromptWhileBusyIsRefusedButPrintingCommandsStillRun() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["review"] = CommandDispatchResult(type: .send, message: "Review the staged diff")
        transport.dispatchReplies["usage"] = CommandDispatchResult(type: .exec, output: "12 tokens today")
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.handle(try envelope("message.start", [:], seq: 1))
        #expect(await controller.send("/review staged") == .notSent)
        #expect(await controller.send("/usage") == .sent)
        await controller.handle(try envelope("message.complete", ["text": "done", "status": "complete"], seq: 2))
        #expect(transport.submitted.isEmpty)
    }

    @Test func aDetachedChatSendsNothingAndTheComposerKeepsTheText() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.detach()
        let photo = ComposerAttachment(kind: .image, name: "IMG_1.jpg", data: Data([1]))
        #expect(await controller.send("look", attachments: [photo]) == .notSent)
        #expect(transport.uploads.isEmpty)
        #expect(transport.submitted.isEmpty)
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

    @Test func skillDirectiveSendsItsPromptAndShowsItsDisplay() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["review"] = CommandDispatchResult(
            type: .skill, message: "Review the staged diff.", display: "Review skill")
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("/review staged")
        #expect(transport.dispatched == [CommandDispatchParams(name: "review", arg: "staged", sessionID: "abcd1234")])
        #expect(transport.submitted.map(\.text) == ["Review the staged diff."])
        let state = await controller.current
        guard case .user(let entry) = state.items.last?.content else {
            Issue.record("no user row")
            return
        }
        #expect(entry.text == "Review skill")
    }

    @Test func prefillDirectiveGivesTheComposerItsTextAndSendsNothing() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["summarize"] = CommandDispatchResult(type: .prefill, message: "Summarize this: ")
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.send("/summarize") == .prefill("Summarize this: "))
        #expect(transport.submitted.isEmpty)
    }

    @Test func execDirectivePrintsItsOutputAndSendsNothing() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["usage"] = CommandDispatchResult(type: .exec, output: "12 tokens today")
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("/usage")
        let state = await controller.current
        #expect(transport.submitted.isEmpty)
        #expect(state.items.last?.content == TranscriptItem.Content.other(role: "system", text: "12 tokens today"))
    }

    @Test func commandTheServerDoesNotKnowGoesOutAsTyped() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.send("/src/main.swift is slow")
        #expect(transport.dispatched.map(\.name) == ["src/main.swift"])
        #expect(transport.submitted.map(\.text) == ["/src/main.swift is slow"])
    }

    @Test func aliasRunsItsTargetWithTheTypedArguments() async throws {
        let transport = try FakeChatTransport()
        transport.dispatchReplies["q"] = CommandDispatchResult(type: .alias, target: "quit")
        transport.dispatchReplies["quit"] = CommandDispatchResult(type: .prefill, message: "Goodbye")
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.send("/q now") == .prefill("Goodbye"))
        #expect(transport.dispatched.map(\.name) == ["q", "quit"])
        #expect(transport.dispatched.last?.arg == "now")
    }

    // MARK: - Persisted sends (WP-3)

    private func record(_ text: String) -> OutboundRecord {
        OutboundRecord(
            connectionID: "x", chatID: "20261015_000000_aaaaaa", text: text, createdAt: Date(timeIntervalSince1970: 0))
    }

    @Test func deliverSendsOnceAndEchoesTheRow() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        let outcome = await controller.deliver(record("hello"))
        #expect(outcome == .acknowledged)
        #expect(transport.submitted.map(\.text) == ["hello"])
        guard case .user(let entry) = await controller.current.items.last?.content else {
            Issue.record("no user row")
            return
        }
        #expect(entry.text == "hello")
        #expect(entry.delivery == .sent)
    }

    @Test func deliverBeforeTheSessionIsLiveDefersInsteadOfDropping() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        let outcome = await controller.deliver(record("hello"))
        #expect(outcome == .deferred)
        #expect(transport.submitted.isEmpty)
    }

    /// A snapshot with no turn running asks the chat to drain again. A deferred message changes nothing, so it must
    /// not publish one: with the socket down that was a submit, fail, drain loop with no pause.
    @Test func aDeferredDeliverPublishesNothingSoItCannotAskForAnotherDrain() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        var snapshots = await controller.states().makeAsyncIterator()
        _ = await snapshots.next()
        transport.failSubmitError = URLError(.notConnectedToInternet)
        #expect(await controller.deliver(record("waiting")) == .deferred)
        let published = Task { await snapshots.next() != nil }
        try await Task.sleep(for: .milliseconds(200))
        published.cancel()
        #expect(await published.value == false)
    }

    @Test func deliverWhileATurnRunsDefersUntilItEnds() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        // The fake answers "streaming", so the turn is under way and the next message must wait.
        #expect(await controller.deliver(record("first")) == .acknowledged)
        #expect(await controller.deliver(record("second")) == .deferred)
        #expect(transport.submitted.map(\.text) == ["first"])
    }

    @Test func sendBeforeTheSessionIsLiveReturnsTheTextToTheComposer() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        #expect(await controller.send("  keep me  ") == .notSent)
        #expect(transport.submitted.isEmpty)
    }

    // MARK: - Stalls and resync (WP-5)

    /// A session with no running turn, as a cold re-attach brings it back.
    private func coldResult() throws -> SessionAttachResult {
        let object: JSONValue = [
            "session_id": "abcd1234", "message_count": .int(0), "messages": .array([]),
            "info": ["model": "m"], "stored_session_id": "20261015_000000_aaaaaa",
        ]
        return try object.decode(SessionAttachResult.self)
    }

    /// A chat with one prompt awaiting its turn and a second saved message that had to wait behind it.
    private func waitingChat() async throws -> (ChatSessionController, FakeChatTransport) {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.deliver(record("first")) == .acknowledged)
        #expect(await controller.deliver(record("second")) == .deferred)
        #expect(transport.submitted.map(\.text) == ["first"])
        return (controller, transport)
    }

    @Test func aColdReattachWithNoTurnRunningLetsTheNextMessageGo() async throws {
        let (controller, transport) = try await waitingChat()
        await controller.handle(.sessionReattached(oldLiveID: "abcd1234", result: try coldResult(), how: .cold))
        #expect(await controller.deliver(record("second")) == .acknowledged)
        #expect(transport.submitted.map(\.text) == ["first", "second"])
    }

    @Test func aFailedResyncStopsWaitingAndTheNextMessageGoes() async throws {
        let (controller, transport) = try await waitingChat()
        await controller.handle(.resyncFailed(sessionID: "abcd1234", message: "gone"))
        #expect(await controller.deliver(record("second")) == .acknowledged)
        #expect(transport.submitted.map(\.text) == ["first", "second"])
    }

    @Test func aFailedResyncIsShownAsAStatusNoteNotAnError() throws {
        var state = TranscriptState(storedSessionID: "20261015_000000_aaaaaa")
        let action = try #require(TranscriptAction(.resyncFailed(sessionID: "abcd1234", message: "gone")))
        state.apply(action)
        #expect(state.connectionNote == "Couldn't read this chat again. Reconnecting.")
        #expect(state.lastError == nil)
        // The next attach clears the note.
        state.apply(.attached(try coldResult()))
        #expect(state.connectionNote == nil)
    }

    @Test func aDetachedChatDefersADelivery() async throws {
        let transport = try FakeChatTransport()
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        await controller.detach()
        #expect(await controller.deliver(record("late")) == .deferred)
        #expect(transport.submitted.isEmpty)
    }

    // MARK: - Failure classification (review M2)

    @Test func aDroppedConnectionDefersTheMessageInsteadOfFailingIt() async throws {
        let transport = try FakeChatTransport()
        transport.failSubmitError = GatewayClientError.notConnected
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.deliver(record("waiting")) == .deferred)
    }

    @Test func aServerRefusalFailsTheMessageWithTheServersWords() async throws {
        let transport = try FakeChatTransport()
        transport.failSubmit = RPCError(code: 5000, message: "Model is not available", data: nil)
        let controller = ChatSessionController(transport: transport, storedSessionID: "20261015_000000_aaaaaa")
        try await controller.attach()
        #expect(await controller.deliver(record("refused")) == .failed("Model is not available"))
    }

    // MARK: - Two chats on one client (review M3)

    @Test func aChatIgnoresTheEventsAndResyncOfAnotherChat() async throws {
        let transport = try FakeChatTransport()
        transport.liveIDs = ["stored-a": "live-a", "stored-b": "live-b"]
        let chatA = ChatSessionController(transport: transport, storedSessionID: "stored-a")
        let chatB = ChatSessionController(transport: transport, storedSessionID: "stored-b")
        try await chatA.attach()
        try await chatB.attach()

        // Chat A's events, a failed resync of A and a cold re-attach of A all reach chat B on the same client.
        let start: JSONValue = ["type": "message.start", "session_id": "live-a", "payload": [:], "seq": 1]
        await chatB.handle(.event(try start.decode(GatewayEventEnvelope.self), replayed: false))
        await chatB.handle(.resyncFailed(sessionID: "live-a", message: "gone"))
        await chatB.handle(
            .sessionReattached(oldLiveID: "live-a", result: try transport.attach(live: "live-a2"), how: .cold))

        let state = await chatB.current
        #expect(state.liveSessionID == "live-b")
        #expect(state.turn == nil)
        #expect(state.connectionNote == nil)
        #expect(state.items.isEmpty)

        // Chat A takes its own cold re-attach.
        await chatA.handle(
            .sessionReattached(oldLiveID: "live-a", result: try transport.attach(live: "live-a2"), how: .cold))
        #expect(await chatA.current.liveSessionID == "live-a2")
    }
}
