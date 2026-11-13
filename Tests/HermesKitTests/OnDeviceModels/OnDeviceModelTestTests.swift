import Foundation
import Testing

@testable import HermesKit

/// A fake model with a name and a literal reply, like "Test-Model-X" in the plan's AT-5c.
private final class NamedModel: LocalModelExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var prompts: [String] = []
    private let reply: String
    private let failure: (any Error)?

    init(reply: String, failure: (any Error)? = nil) {
        self.reply = reply
        self.failure = failure
    }

    var received: [String] { lock.withLock { prompts } }
    var availability: LocalModelAvailability { .available }
    func respond(instructions: String, prompt: String) async throws -> String {
        lock.withLock { prompts.append(prompt) }
        if let failure { throw failure }
        return reply
    }
}

private final class OneModelRuntime: OnDeviceModelRuntime, @unchecked Sendable {
    let model: NamedModel
    init(_ model: NamedModel) { self.model = model }
    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? { self.model }
    func unloadAll() async {}
}

private final class Keeper: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [TestEnvironment] = []
    func keep(_ environment: TestEnvironment) { lock.withLock { kept.append(environment) } }
}
private let keeper = Keeper()

/// A clock that moves one second each time it is read.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func now() -> Double {
        lock.withLock {
            defer { value += 1.5 }
            return value
        }
    }
}

/// WP-10: "Use and test" names the executor that really answered, with the time it took.
struct OnDeviceModelTestTests {
    private let alpha = TestModels.alpha

    private func selection(_ model: NamedModel?) throws -> OnDeviceModelSelection {
        let env = TestEnvironment()
        keeper.keep(env)
        try env.installFinished(alpha)
        return OnDeviceModelSelection(
            apple: StubExecutor(name: "apple"), storage: env.storage, catalog: TestModels.catalog,
            runtime: model.map(OneModelRuntime.init))
    }

    @Test func useAndTestSelectsTheModelAndShowsWhoAnsweredWithTheTime() async throws {
        let model = NamedModel(reply: "I am a small test model.")
        let selection = try selection(model)
        let clock = StepClock()
        let outcome = await selection.useAndTest(.downloaded("alpha"), now: { clock.now() })

        let expected = ModelTestResult(
            answeredBy: .downloaded(id: alpha.id, displayName: alpha.displayName), seconds: 1.5,
            reply: "I am a small test model.")
        #expect(outcome == .passed(expected))
        #expect(selection.choice == .downloaded("alpha"))
        #expect(model.received == [OnDeviceModelSelection.testPrompt])
    }

    @Test func theTestAndAChatReplyNameTheSameExecutor() async throws {
        let model = NamedModel(reply: "hello")
        let selection = try selection(model)
        guard case .passed(let tested) = await selection.useAndTest(.downloaded("alpha")) else {
            Issue.record("the test should pass")
            return
        }
        let chatAnswer = try await selection.answer(instructions: "x", prompt: "hi")
        #expect(chatAnswer.answeredBy == tested.answeredBy)
    }

    @Test func aModelThatCannotRunIsReportedAndNothingElseAnswersInItsPlace() async throws {
        let selection = try selection(nil)
        let outcome = await selection.useAndTest(.downloaded("alpha"))
        guard case .cannotRun(.failed(let identity, .runtimeUnavailable)) = outcome else {
            Issue.record("expected cannotRun, got \(outcome)")
            return
        }
        #expect(identity == .downloaded(id: alpha.id, displayName: alpha.displayName))
    }

    @Test func aModelThatReturnsNothingFailsTheTest() async throws {
        let outcome = await (try selection(NamedModel(reply: "  \n"))).useAndTest(.downloaded("alpha"))
        #expect(outcome == .failed("The model returned nothing."))
    }

    @Test func aModelThatThrowsFailsTheTestWithItsError() async throws {
        let model = NamedModel(reply: "", failure: TestFailure(message: "out of tokens"))
        let outcome = await (try selection(model)).useAndTest(.downloaded("alpha"))
        guard case .failed(let text) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(text.contains("out of tokens"))
    }

    @Test func testModelRunsAnytimeOnWhateverIsChosen() async throws {
        let selection = try selection(NamedModel(reply: "again"))
        await selection.select(.downloaded("alpha"))
        guard case .passed(let result) = await selection.test() else {
            Issue.record("the test should pass")
            return
        }
        #expect(result.reply == "again")
    }
}
