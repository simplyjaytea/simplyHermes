import Foundation

/// Why on-device helpers cannot run right now.
public enum LocalModelUnavailable: Sendable, Equatable {
    /// The device does not support Apple Intelligence.
    case unsupported
    /// Apple Intelligence is off in Settings.
    case disabled
    /// The model is still downloading or preparing.
    case notReady
    /// The user turned on-device features off in simplyHermes (plan WP-65b switch).
    case switchedOff
}

/// Whether an on-device model can answer.
public enum LocalModelAvailability: Sendable, Equatable {
    case available
    case unavailable(LocalModelUnavailable)
}

/// Runs a prompt on a model that lives on the device. The app supplies the Apple implementation; tests supply a mock.
public protocol LocalModelExecutor: Sendable {
    /// Whether the model can answer now.
    var availability: LocalModelAvailability { get }
    /// Answers `prompt` guided by `instructions`.
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Small jobs for the on-device model: chat titles, summaries and prompt polish. Each one returns nil when the model
/// is unavailable or fails, so callers fall back to what they had.
public struct LocalHelpers: Sendable {
    /// Text longer than this many characters is summarized in pieces first.
    public static let chunkSize = 6000
    /// Titles longer than this are cut.
    public static let maxTitleLength = 60

    private let executor: any LocalModelExecutor

    public init(executor: any LocalModelExecutor) {
        self.executor = executor
    }

    /// True when the model can answer.
    public var isAvailable: Bool { executor.availability == .available }

    /// A short title for a chat, from its first user message and the first reply if there is one.
    public func title(userText: String, replyText: String? = nil) async -> String? {
        var prompt = "User: \(userText.prefix(1000))"
        if let replyText { prompt += "\nAssistant: \(replyText.prefix(1000))" }
        let instructions = "Write a title of at most six words for this chat. Reply with the title only, no quotes."
        guard let raw = await run(instructions, prompt) else { return nil }
        return Self.cleanTitle(raw)
    }

    /// A summary of long text. Text over ``chunkSize`` is summarized in pieces, then the pieces are joined and
    /// summarized once more.
    public func summary(of text: String) async -> String? {
        let instructions = "Summarize the text in a few short sentences. Keep names, numbers and decisions."
        let pieces = Self.chunks(of: text, size: Self.chunkSize)
        guard !pieces.isEmpty else { return nil }
        if pieces.count == 1 { return await run(instructions, pieces[0]) }
        var partials: [String] = []
        for piece in pieces {
            guard let part = await run(instructions, piece) else { return nil }
            partials.append(part)
        }
        return await run(instructions, partials.joined(separator: "\n\n"))
    }

    /// A clearer version of a draft prompt. Meaning stays; wording gets tighter.
    public func polish(_ draft: String) async -> String? {
        let instructions = """
            Rewrite the message to be clear and direct. Keep its meaning, language and any code or paths exactly. \
            Reply with the rewritten message only.
            """
        return await run(instructions, draft)
    }

    private func run(_ instructions: String, _ prompt: String) async -> String? {
        guard executor.availability == .available else { return nil }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let answer = try? await executor.respond(instructions: instructions, prompt: trimmed) else { return nil }
        let result = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Strips quotes and a trailing period, keeps the first line, and cuts to ``maxTitleLength``.
    static func cleanTitle(_ raw: String) -> String? {
        var title = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ ."))
        if title.count > maxTitleLength {
            title = String(title.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : title
    }

    /// Splits text into pieces of at most `size` characters, preferring to cut at a blank line, then a line end.
    static func chunks(of text: String, size: Int) -> [String] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return [] }
        var pieces: [String] = []
        var rest = Substring(source)
        while rest.count > size {
            let window = rest.prefix(size)
            let cut =
                window.range(of: "\n\n", options: .backwards)?.upperBound
                ?? window.range(of: "\n", options: .backwards)?.upperBound
                ?? window.endIndex
            pieces.append(String(rest[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[cut...]
        }
        let last = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { pieces.append(last) }
        return pieces
    }
}
