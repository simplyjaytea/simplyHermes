import Foundation

/// Which way Up or Down moves through the sent messages of a chat.
public enum ComposerRecallDirection: Sendable, Equatable {
    /// Up: the message before the one shown.
    case older
    /// Down: the message after the one shown, or back to the text the user was writing.
    case newer
}

/// The messages sent in one chat, the text that the last send or clear took out of its field, and where Up and Down
/// are in the history. The composer keeps one per chat.
public struct ComposerHistory: Sendable, Equatable {
    /// Most messages kept. The oldest fall off first.
    public static let limit = 50

    /// Messages sent in this chat, oldest first.
    public private(set) var sent: [String] = []
    /// Text that a send or a clear took out of the field. Undo puts it back once.
    public private(set) var cleared: String?
    /// The entry Up and Down show, or nil while the field holds the user's own text.
    public private(set) var position: Int?
    /// The text the user was writing when Up started the walk through history.
    private var ownText = ""

    /// Creates an empty history.
    public init() {}

    /// Adds a sent message. Blank text is ignored.
    public mutating func remember(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sent = Array((sent + [trimmed]).suffix(Self.limit))
        position = nil
    }

    /// Keeps text that a send or a clear removed from the field, so Undo can bring it back.
    public mutating func keepCleared(_ text: String) {
        if !text.isEmpty { cleared = text }
    }

    /// Returns the text that Undo restores, and forgets it. Nil when nothing was kept.
    public mutating func takeCleared() -> String? {
        defer { cleared = nil }
        return cleared
    }

    /// Moves Up or Down through the history. `current` is the text in the field. Returns the text to show, or nil
    /// when the key does not move anything. Up starts only from an empty field, so it never takes the caret away from
    /// text the user is still writing.
    public mutating func step(_ direction: ComposerRecallDirection, current: String) -> String? {
        if let index = position {
            let next: Int
            switch direction {
            case .older:
                next = max(index - 1, 0)
            case .newer:
                guard index + 1 < sent.count else {
                    position = nil
                    return ownText
                }
                next = index + 1
            }
            position = next
            return sent[next]
        }
        guard direction == .older, current.isEmpty, !sent.isEmpty else { return nil }
        ownText = current
        position = sent.count - 1
        return sent[sent.count - 1]
    }

    /// Call with the field's text after each change. Editing the text of an entry ends the walk, so the edit stays.
    public mutating func noteEdit(_ text: String) {
        guard let index = position, sent.indices.contains(index), sent[index] != text else { return }
        position = nil
    }
}
