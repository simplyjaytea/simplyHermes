/// Messages the user wrote while Hermes was busy. They wait on the phone, can be edited, reordered and removed,
/// and are sent one at a time when the turn ends, unless the queue is paused.
public struct MessageQueue: Sendable, Equatable {
    /// One waiting message.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: Int
        public var text: String
    }

    /// The waiting messages, next to send first.
    public private(set) var entries: [Entry] = []
    /// True while the user holds the queue. Nothing is sent until it resumes.
    public var isPaused = false
    private var nextID = 1

    /// Creates an empty queue.
    public init() {}

    /// True when nothing waits.
    public var isEmpty: Bool { entries.isEmpty }

    /// Adds a message at the end. Blank text is ignored. Returns the new entry id.
    @discardableResult
    public mutating func enqueue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, text: trimmed))
        return id
    }

    /// Replaces the text of an entry. Blank text removes it.
    public mutating func edit(_ id: Int, to text: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            entries.remove(at: index)
        } else {
            entries[index].text = trimmed
        }
    }

    /// Removes an entry.
    public mutating func remove(_ id: Int) {
        entries.removeAll { $0.id == id }
    }

    /// Moves an entry to a new position in the list (clamped to the ends).
    public mutating func move(_ id: Int, to position: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: min(max(position, 0), entries.count))
    }

    /// Takes the next message to send, or nil when the queue is empty or paused.
    public mutating func takeNext() -> Entry? {
        guard !isPaused, !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    /// Puts a message back at the front, for a send that failed before the server saw it.
    public mutating func restoreFront(_ entry: Entry) {
        entries.insert(entry, at: 0)
    }
}

/// Everything the chat screen reads from a ``ChatSessionController``.
public struct ChatSnapshot: Sendable, Equatable {
    public var transcript: TranscriptState
    public var queue: MessageQueue
}
