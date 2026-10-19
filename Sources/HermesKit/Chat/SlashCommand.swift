import Foundation

/// A message that starts with a slash command: the command name and the text after it.
public struct SlashCommand: Sendable, Equatable {
    /// The command name, without the slash.
    public var name: String
    /// The text after the name, trimmed. Nil when there is none.
    public var arg: String?

    /// Splits a message. Nil unless it starts with a slash followed by a name.
    public init?(_ text: String) {
        guard text.hasPrefix("/") else { return nil }
        let body = text.dropFirst()
        let name = body.prefix { !$0.isWhitespace }
        guard !name.isEmpty else { return nil }
        let arg = body.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = String(name)
        self.arg = arg.isEmpty ? nil : arg
    }
}
