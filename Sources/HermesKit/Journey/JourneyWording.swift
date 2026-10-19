import Foundation

// The words of the node sheet (WP-52). They live here, away from the views, so the promise they make is tested: deleting
// a skill archives it, and deleting a memory chunk removes it. That is what the server does (`learning_mutations`):
// a skill moves to the curator archive and can be restored with `hermes curator restore`, a memory chunk is cut out of
// `MEMORY.md` or `USER.md`, and a pinned skill is refused.

extension JourneyNode {
    /// The question of the delete confirmation.
    public var deleteTitle: String {
        kind == .memory ? "Delete this memory?" : "Delete \u{201C}\(label)\u{201D}?"
    }

    /// What the delete does, in the server's terms: a skill is archived, a memory chunk is removed.
    public var deleteMessage: String {
        switch kind {
        case .skill:
            "Skills are archived, not erased. \u{201C}\(label)\u{201D} moves to the archive on the server. "
                + "To bring it back, run: hermes curator restore \(id)"
        case .memory:
            "Memories are removed, not archived. This text is deleted from the agent\u{2019}s memory and cannot be "
                + "brought back."
        case .other:
            "The server decides whether this is archived or removed. It may not be possible to bring it back."
        }
    }

    /// What the user reads after a delete went through.
    public var deletedNotice: String {
        switch kind {
        case .skill: "Archived \u{201C}\(label)\u{201D}."
        case .memory: "Removed the memory."
        case .other: "Deleted \u{201C}\(label)\u{201D}."
        }
    }

    /// What the user reads after a save went through.
    public var savedNotice: String {
        kind == .memory ? "Saved the memory." : "Saved \u{201C}\(label)\u{201D}."
    }

    /// Why Delete is off, for a pinned skill. The server refuses to delete one.
    public var deleteBlocker: String? {
        pinned ? "A pinned skill cannot be deleted. Unpin it on the server first." : nil
    }

    /// What VoiceOver reads for the node: its name, its facts, then when it was last touched.
    public var spokenSummary: String {
        var parts = [label] + detailParts
        if let date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: ", ")
    }
}
