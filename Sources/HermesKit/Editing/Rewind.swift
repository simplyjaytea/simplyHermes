/// How a rewind ended (WP-34).
public enum RewindOutcome: Sendable, Equatable {
    /// The chat was cut at the turn and shows the server's history. `text` is the turn's text, for the composer.
    case done(text: String)
    /// Ask the user, then call again with ``TurnEditConfirmation/consent``.
    case needsConfirmation(TurnEditConfirmation)
    /// The server's turns from that message on were not the ones on screen, or `session.undo` did not take them
    /// all. The chat shows the server's history now, and nothing more is cut.
    case changed
    /// Hermes is still replying, and `session.undo` needs an idle session.
    case busy
    /// A call failed. Turns the server dropped before that stay dropped, and the chat shows what the server kept.
    case failed(RPCError)
}

extension RewindImpact {
    /// The row ids of the user turns from the row `rowID` on, oldest first. Nil when no user row in `items` has that
    /// id. Rows without an id are left out: a send that failed or was never acknowledged is not stored by the server,
    /// so `session.undo` cannot drop it.
    static func userRowIDs(in items: [TranscriptItem], from rowID: Int) -> [Int]? {
        guard
            let start = items.firstIndex(where: {
                if case .user(let entry) = $0.content { return entry.rowID == rowID }
                return false
            })
        else { return nil }
        return items[start...].compactMap { item -> Int? in
            if case .user(let entry) = item.content { return entry.rowID }
            return nil
        }
    }

    /// True when both lists hold the same user turns from `rowID` on. A cut at `rowID` then takes what the user sees
    /// and nothing else. False when either list lacks the row.
    static func agree(_ server: [TranscriptItem], _ local: [TranscriptItem], from rowID: Int) -> Bool {
        guard let theirs = userRowIDs(in: server, from: rowID) else { return false }
        return theirs == userRowIDs(in: local, from: rowID)
    }
}
