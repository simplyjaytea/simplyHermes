import Foundation

/// Answers a local chat's message and names the model that did it. A local chat only ever asks this; it never sees a
/// transport or a server.
public protocol LocalChatAnswerer: Sendable {
    /// Whether a model can answer now.
    var availability: LocalModelAvailability { get }
    /// Answers `prompt` guided by `instructions`, with the model that answered.
    func answer(instructions: String, prompt: String) async throws -> LocalAnswer
}

/// Answers with one fixed executor and names it. Used for the Apple model, for a test fake, and for a fake the UI
/// test launch argument picks.
public struct FixedModelAnswerer: LocalChatAnswerer {
    private let identity: ModelIdentity
    private let executor: any LocalModelExecutor

    /// Creates an answerer that stamps every reply with `identity`.
    public init(identity: ModelIdentity, executor: any LocalModelExecutor) {
        self.identity = identity
        self.executor = executor
    }

    public var availability: LocalModelAvailability { executor.availability }

    public func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
        let text = try await executor.respond(instructions: instructions, prompt: prompt)
        return LocalAnswer(text: text, answeredBy: identity)
    }
}
