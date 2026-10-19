import Foundation

/// A room's events as the app holds them: each log read merged in by sequence number, and where the next read starts
/// (WP-43 spec, section 3).
public struct RoomTranscript: Sendable, Equatable {
    /// Events in sequence order, one per sequence number.
    public private(set) var events: [RoomEvent] = []
    /// Where the next log read starts (`since_seq`).
    public private(set) var cursor = 0

    public init() {}

    /// Adds a read's events. An event already held is skipped, so a read that repeats one changes nothing.
    public mutating func merge(_ log: RoomLog) {
        let held = Set(events.map(\.seq))
        events += log.events.filter { !held.contains($0.seq) }
        events.sort { $0.seq < $1.seq }
        cursor = max(cursor, log.cursor)
    }

    /// Starts over, after the server reports the cursor ahead of its log.
    public mutating func reset() {
        events = []
        cursor = 0
    }

    /// The transcript rows for the events held.
    public func rows(labels: [String: String]) -> [RoomRow] {
        RoomTimeline.rows(from: events, labels: labels)
    }
}

/// One message on its way to a room. Its ids are minted once and reused on every retry, so the server stores the
/// message once (WP-43 spec, section 2).
public struct RoomOutgoingMessage: Sendable, Equatable {
    /// The text as sent: trimmed, never blank.
    public let text: String
    /// The retry key for this message.
    public let eventID: String
    /// The thread this message starts.
    public let threadID: String

    /// A message for `text`, or nil when the text is blank.
    public init?(text: String, now: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
        eventID = RoomIdentifier.newEventID()
        threadID = RoomIdentifier.newThreadID(now: now)
    }
}

extension RoomStatus {
    /// Seconds to wait before the next state read: one while the room works, five while it idles (WP-43 spec, section 3).
    public static func pollInterval(for status: RoomDriverStatus?) -> TimeInterval {
        status?.working == true ? 1 : 5
    }
}
