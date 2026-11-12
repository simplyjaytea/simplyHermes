import Foundation

/// What a model test showed: which model answered, how long it took, and what it said.
public struct ModelTestResult: Sendable, Equatable {
    /// The model that wrote the reply, as the executor reported it.
    public let answeredBy: ModelIdentity
    /// Seconds from the start of the test, including loading the model.
    public let seconds: Double
    /// The reply, as the model wrote it. Never edited and never made up here.
    public let reply: String

    public init(answeredBy: ModelIdentity, seconds: Double, reply: String) {
        self.answeredBy = answeredBy
        self.seconds = seconds
        self.reply = reply
    }
}

/// How a model test ended.
public enum ModelTestOutcome: Sendable, Equatable {
    /// The model answered.
    case passed(ModelTestResult)
    /// The model could not run. The status says why; nothing else answered in its place.
    case cannotRun(LocalModelStatus)
    /// The model ran and failed or returned nothing. The text is for the user.
    case failed(String)
}

extension OnDeviceModelSelection {
    /// The fixed test prompt (WP-10). It asks for a short reply, so the test is quick on a small model.
    public static let testInstructions = "Be brief."
    public static let testPrompt = "Reply with one short sentence."

    /// "Use and test": selects the model, loads it, and sends the fixed prompt through the **same path chat uses**
    /// (``answer(instructions:prompt:)``), so the result names the executor that really answered.
    public func useAndTest(
        _ choice: OnDeviceModelChoice, now: @Sendable () -> Double = OnDeviceModelSelection.monotonicNow
    ) async -> ModelTestOutcome {
        await select(choice)
        return await test(now: now)
    }

    /// "Test model": tests whatever is chosen now, at any time.
    public func test(
        now: @Sendable () -> Double = OnDeviceModelSelection.monotonicNow
    ) async -> ModelTestOutcome {
        let started = now()
        let prepared = await prepare()
        switch prepared {
        case .ready:
            break
        case .failed, .noModel, .off, .verifying, .loading, .notLoaded, .downloading:
            return .cannotRun(prepared)
        }
        do {
            let answer = try await self.answer(instructions: Self.testInstructions, prompt: Self.testPrompt)
            guard !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failed("The model returned nothing.")
            }
            return .passed(
                ModelTestResult(answeredBy: answer.answeredBy, seconds: now() - started, reply: answer.text))
        } catch {
            return .failed("\(error)")
        }
    }

    /// Seconds on a monotonic scale. Only differences are meaningful.
    public static let monotonicNow: @Sendable () -> Double = {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
