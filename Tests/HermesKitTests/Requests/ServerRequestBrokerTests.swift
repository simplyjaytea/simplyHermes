import Foundation
import Testing

@testable import HermesKit

@Suite struct ServerRequestBrokerTests {
    private func request(_ id: String, _ method: String, _ params: JSONValue) -> RPCRequest {
        RPCRequest(id: .string(id), method: method, params: params as JSONValue?)
    }

    private let approval = JSONValue.object([
        "session_id": "s1", "request_id": "r1", "command": "rm -rf build",
    ])
    private let clarify = JSONValue.object([
        "session_id": "s1",
        "questions": .array([
            .object(["qid": "q0", "question": "Which?", "choices": .array(["a", "b"])]),
            .object(["qid": "q1", "question": "Notes?"]),
        ]),
    ])

    /// Starts `handle` and waits until the broker lists the request.
    private func start(_ broker: ServerRequestBroker, _ request: RPCRequest) async -> Task<JSONValue, any Error> {
        let task = Task { try await broker.handle(request) }
        guard case .string(let waitID) = request.id else { return task }
        for _ in 0..<500 {
            if await broker.pending.contains(where: { $0.id == waitID }) { break }
            await Task.yield()
        }
        return task
    }

    @Test func approvalAnswerBecomesTheResult() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "approval", approval))
        #expect(await broker.pending.map(\.id) == ["srq-1"])
        try await broker.answer("srq-1", with: .approval(.init(choice: .once)))
        let result = try await task.value
        #expect(result == .object(["choice": "once"]))
        #expect(await broker.pending.isEmpty)
    }

    @Test func requestsKeepArrivalOrder() async throws {
        let broker = ServerRequestBroker()
        let first = await start(broker, request("srq-1", "approval", approval))
        let second = await start(broker, request("srq-2", "clarify", clarify))
        #expect(await broker.pending.map(\.id) == ["srq-1", "srq-2"])
        try await broker.answer("srq-1", with: .approval(.init(choice: .deny)))
        #expect(await broker.pending.map(\.id) == ["srq-2"])
        try await broker.answer("srq-2", with: .clarify(.init(answers: ["q0": "a", "q1": "x"])))
        _ = try await (first.value, second.value)
    }

    @Test func wrongAnswerTypeIsRefusedAndTheRequestStaysOpen() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "approval", approval))
        await #expect(throws: ServerRequestError.wrongAnswer(method: "approval")) {
            try await broker.answer("srq-1", with: .value(.init(value: "x")))
        }
        #expect(await broker.pending.count == 1)
        task.cancel()
    }

    @Test func clarifyAnswersAreChecked() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "clarify", clarify))
        await #expect(throws: ServerRequestError.invalidClarifyAnswer(qid: "zz")) {
            try await broker.answer("srq-1", with: .clarify(.init(answers: ["zz": "a"])))
        }
        await #expect(throws: ServerRequestError.invalidClarifyAnswer(qid: "q0")) {
            try await broker.answer("srq-1", with: .clarify(.init(answers: ["q0": ""])))
        }
        try await broker.answer("srq-1", with: .clarify(.init(answers: ["q0": "b", "q1": ""])))
        #expect(try await task.value == .object(["answers": .object(["q0": "b", "q1": ""])]))
    }

    @Test func emptySecretIsRefused() async throws {
        let broker = ServerRequestBroker()
        let params = JSONValue.object(["session_id": "s1", "env_var": "API_KEY", "prompt": "Key?"])
        let task = await start(broker, request("srq-1", "secret", params))
        await #expect(throws: ServerRequestError.emptyValue) {
            try await broker.answer("srq-1", with: .value(.init(value: "")))
        }
        try await broker.answer("srq-1", with: .value(.init(value: "k")))
        #expect(try await task.value == .object(["value": "k"]))
    }

    @Test func answeringTwiceFails() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "sudo", .object(["session_id": "s1"])))
        try await broker.answer("srq-1", with: .value(.init(value: "pw")))
        _ = try await task.value
        await #expect(throws: ServerRequestError.notPending("srq-1")) {
            try await broker.answer("srq-1", with: .value(.init(value: "pw")))
        }
    }

    @Test func cancelDropsTheRequestAndEndsTheHandlerWithoutAReply() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "approval", approval))
        await broker.cancel("srq-1")
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await broker.pending.isEmpty)
    }

    @Test func cancellingTheHandlerTaskDropsTheRequest() async throws {
        let broker = ServerRequestBroker()
        let task = await start(broker, request("srq-1", "approval", approval))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await broker.pending.isEmpty)
    }

    @Test func cancelAllEndsEveryHandler() async throws {
        let broker = ServerRequestBroker()
        let one = await start(broker, request("srq-1", "approval", approval))
        let two = await start(broker, request("srq-2", "clarify", clarify))
        await broker.cancelAll()
        await #expect(throws: CancellationError.self) { try await one.value }
        await #expect(throws: CancellationError.self) { try await two.value }
    }

    @Test func updatesStartWithTheCurrentListAndFollowChanges() async throws {
        let broker = ServerRequestBroker()
        var updates = await broker.updates().makeAsyncIterator()
        #expect(await updates.next()?.isEmpty == true)
        let task = await start(broker, request("srq-1", "approval", approval))
        #expect(await updates.next()?.map(\.id) == ["srq-1"])
        task.cancel()
        _ = try? await task.value
        #expect(await updates.next()?.isEmpty == true)
    }

    @Test func malformedParamsThrowInsteadOfWaiting() async throws {
        let broker = ServerRequestBroker()
        await #expect(throws: (any Error).self) {
            _ = try await broker.handle(request("srq-1", "approval", .object([:])))
        }
        #expect(await broker.pending.isEmpty)
    }

    @Test func secretValuesNeverShowInTextOrDumps() {
        let answer = ValueAnswer(value: "hunter2-very-secret")
        var dumped = ""
        dump(answer, to: &dumped)
        let texts = [
            "\(answer)", String(describing: answer), String(reflecting: answer), dumped,
            "\(ServerAnswer.value(answer))", String(reflecting: ServerAnswer.value(answer)),
        ]
        for text in texts { #expect(!text.contains("hunter2")) }
    }
}
