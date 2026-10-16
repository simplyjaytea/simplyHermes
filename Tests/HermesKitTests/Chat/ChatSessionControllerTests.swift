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
    var failSubmit: RPCError?

    init(history: [JSONValue] = []) throws {
        let object: JSONValue = [
            "session_id": "abcd1234", "message_count": .int(history.count), "messages": .array(history),
            "info": ["model": "m"], "stored_session_id": "20261015_000000_aaaaaa",
        ]
        attachResult = try object.decode(SessionAttachResult.self)
    }

    func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult { attachResult }

    func clientEvents() async -> AsyncStream<GatewayClientEvent> {
        let (stream, continuation) = AsyncStream<GatewayClientEvent>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func submitPrompt(_ params: PromptSubmitParams) async throws -> PromptSubmitResult {
        lock.withLock { submitted.append(params) }
        if let failSubmit { throw failSubmit }
        return try JSONDecoder().decode(
            PromptSubmitResult.self, from: Data(#"{"status":"streaming","user_row_id":9}"#.utf8))
    }

    func steerSession(_ params: SessionSteerParams) async throws { lock.withLock { steered.append(params.text) } }

    func interruptSession(_ params: SessionInterruptParams) async throws { lock.withLock { interrupts += 1 } }
}

private func envelope(_ type: String, _ payload: JSONValue, seq: Int) throws -> GatewayClientEvent {
    let object: JSONValue = ["type": .string(type), "session_id": "abcd1234", "payload": payload, "seq": .int(seq)]
    return .event(try object.decode(GatewayEventEnvelope.self), replayed: false)
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
}
