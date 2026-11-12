import Foundation

/// The "new reply" dot on the scroll-to-latest button (row 74, proposals rev 2 §D). When assistant text arrives while
/// the user has scrolled up, the button shows a dot, and VoiceOver hears "New reply" once per reply.
///
/// Only assistant rows count. User rows, tool calls, notices (`.other`) and gateway-started disclosures
/// (`displayKind`) never light it. What is already in the chat when it opens never lights it.
public struct NewReplyDot: Sendable, Equatable {
    /// The dot is on.
    public private(set) var isShowing = false
    /// Text length of each assistant row seen so far. Nil until the first ``update(items:isFollowing:)``.
    private var lengths: [String: Int]?
    private var announced: Set<String> = []
    /// The chat being followed. The chat screen is reused when the user switches chats, so a new id starts over.
    private var chatID: String?

    public init() {}

    /// Reads the transcript of `chatID` after a change. Returns the id of a reply to announce, at most once per
    /// reply. The first call for a chat, including after a switch to another chat, only records what is there.
    public mutating func update(chatID: String, items: [TranscriptItem], isFollowing: Bool) -> String? {
        if chatID != self.chatID {
            self = NewReplyDot()
            self.chatID = chatID
        }
        var current: [String: Int] = [:]
        var grown: [String] = []
        for item in items {
            guard case .assistant(let entry) = item.content, entry.displayKind == nil else { continue }
            let length = entry.text.count
            current[item.id] = length
            if let lengths, length > (lengths[item.id] ?? 0) { grown.append(item.id) }
        }
        lengths = current
        if isFollowing {
            isShowing = false
            return nil
        }
        guard let newest = grown.last else { return nil }
        isShowing = true
        return announced.insert(newest).inserted ? newest : nil
    }

    /// The user is back at the live end (scrolled there, or tapped the button).
    public mutating func reachedBottom() {
        isShowing = false
    }
}
