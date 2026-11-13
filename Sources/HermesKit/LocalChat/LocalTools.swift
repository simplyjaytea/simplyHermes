import Foundation

// Local agent abilities, phase 2 (spec: Shared/simplyhermes-local-agent-abilities-spec-2026-11-12.md). The on-device
// model may call tools from a closed, reviewed set. Each tool reads or writes only the app's own storage or files the
// user picked; none opens a network connection. Today the set is memory_save.

/// The only tools a local chat can have. A closed enum: a new tool is a reviewed code change, never data
/// (``LocalToolGuardTests`` pins this list).
public enum LocalToolName: String, CaseIterable, Sendable {
    /// Saves one fact about the user to on-device memory. Writes app storage only.
    case memorySave = "memory_save"
}

/// One tool call the model asked for.
public struct LocalToolCall: Sendable, Equatable {
    public var name: LocalToolName
    public var arguments: [String: String]

    public init(name: LocalToolName, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }

    /// The call in a model's answer, or nil when the answer is ordinary text. Strict: the whole answer must be one
    /// fenced ```tool_call block holding `{"name": …, "arguments": {…}}` with string arguments, naming a known tool.
    /// Anything else (extra text, bad JSON, an unknown tool) is text, shown as the model wrote it, never "fixed".
    public static func parse(_ answer: String) -> LocalToolCall? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = "```tool_call"
        guard trimmed.hasPrefix(open), trimmed.hasSuffix("```"), trimmed.count > open.count + 3 else { return nil }
        let body = trimmed.dropFirst(open.count).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.contains("```"),
            let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
            Set(object.keys) == ["name", "arguments"],
            let rawName = object["name"] as? String, let name = LocalToolName(rawValue: rawName),
            let arguments = object["arguments"] as? [String: String]
        else { return nil }
        return LocalToolCall(name: name, arguments: arguments)
    }

    /// What the instructions say about the tools, for a model that can call them.
    public static let instructions = """
        You may save one short fact the user tells you about themselves, so later chats know it. To save, reply with \
        only this block and nothing else:
        ```tool_call
        {"name": "memory_save", "arguments": {"text": "<the fact, one sentence>"}}
        ```
        You will be told the result; then answer the user normally. Save only what the user said about themselves.
        """
}

/// What happens to a memory the model wants to save (Janet, 2026-11-12): saved at once with Undo, but asked first
/// when the turn read a file, because a file can carry instructions that must not plant memories quietly.
public enum LocalMemoryAutoSave: Sendable, Equatable {
    case save(String)
    case askFirst(String)
    case refuse(LocalMemoryError)

    public static func decide(text: String?, turnReadAFile: Bool) -> LocalMemoryAutoSave {
        let clean: String
        do {
            clean = try LocalMemoryRules.validated(text ?? "")
        } catch {
            return .refuse(error)
        }
        return turnReadAFile ? .askFirst(clean) : .save(clean)
    }

    /// The tool result the model is told.
    public var toolResult: String {
        switch self {
        case .save: "Saved to the user's memory. They can undo it."
        case .askFirst: "The user is asked whether to save it."
        case .refuse(.empty): "Not saved: the text was empty."
        case .refuse(.tooLong): "Not saved: keep it under \(LocalMemoryRules.itemLimit) characters."
        case .refuse: "Not saved."
        }
    }
}
