import Foundation

/// Where an outgoing message goes.
public enum OutboundTarget: Equatable, Sendable {
    /// A new chat.
    case newChat
    /// The chat the user used last.
    case lastUsed
    /// One chat, by its session id.
    case chat(String)
}

/// A message on its way into a chat. Siri and Shortcuts, Quick Entry and the Share extension all produce these.
public struct OutboundMessage: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var attachments: [ComposerAttachment]
    public var target: OutboundTarget
    public var createdAt: Date
    /// The bot (Hermes profile) a new chat for this message works as. Nil follows the chosen profile.
    public var profile: String?

    public init(
        id: String = UUID().uuidString, text: String, attachments: [ComposerAttachment] = [],
        target: OutboundTarget, createdAt: Date, profile: String? = nil
    ) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.target = target
        self.createdAt = createdAt
        self.profile = profile
    }
}

/// Whether a server chat can take a message yet. A chat connects when its screen opens.
public enum ChatReadiness: Equatable, Sendable {
    case loading
    case ready
    case failed
}

/// Which chat a waiting message belongs to.
public enum OutboundResolution: Equatable, Sendable {
    /// The chat list may still be loading. Look again soon.
    case wait
    /// There is no such chat to use. Start a new one so the message is kept.
    case createChat
    case chat(String)
}

/// What to do with a message whose chat is known.
public enum OutboundStep: Equatable, Sendable {
    case wait
    /// The chat takes the message now.
    case send
    /// The chat will not take it in time. Leave it in the composer so nothing is lost.
    case saveAsDraft
}

/// Decides where and when an outgoing message is delivered.
///
/// A cold start is the hard case. An intent can launch the app, and the chat list loads only once the shell is on
/// screen. So a message never assumes its chat exists: it waits a little for the list, then for the chat to connect,
/// and falls back to a draft. The functions are pure; the app calls them again and again until a message is done.
public enum OutboundPlanner {
    /// How long a message waits for the chat list before it gives up on its chat.
    public static let listPatience: TimeInterval = 8
    /// How long a message waits for a chat to connect before it is left in the composer.
    public static let connectPatience: TimeInterval = 20

    /// Picks the chat for a message.
    ///
    /// - Parameters:
    ///   - bound: the chat an earlier call created for this message, if any.
    ///   - knownChatIDs: every chat the shell lists right now.
    ///   - lastUsedID: the chat the user used last, if there is one.
    public static func resolve(
        _ message: OutboundMessage, bound: String?, knownChatIDs: Set<String>, lastUsedID: String?, now: Date
    ) -> OutboundResolution {
        if let bound { return .chat(bound) }
        let wanted: String
        switch message.target {
        case .newChat:
            return .createChat
        case .chat(let id):
            wanted = id
        case .lastUsed:
            guard let lastUsedID else { return .createChat }
            wanted = lastUsedID
        }
        if knownChatIDs.contains(wanted) { return .chat(wanted) }
        return now.timeIntervalSince(message.createdAt) < listPatience ? .wait : .createChat
    }

    /// Decides whether the chosen chat takes the message now.
    ///
    /// - Parameters:
    ///   - isLive: the chat is a server chat. Placeholder chats take a message at once.
    ///   - readiness: how far that server chat is along. Ignored for placeholder chats.
    public static func step(
        for message: OutboundMessage, isLive: Bool, readiness: ChatReadiness, now: Date
    ) -> OutboundStep {
        guard isLive else { return .send }
        switch readiness {
        case .ready:
            return .send
        case .failed:
            return .saveAsDraft
        case .loading:
            return now.timeIntervalSince(message.createdAt) < connectPatience ? .wait : .saveAsDraft
        }
    }

    /// The draft text after adding a message that could not be sent: below what the user already typed.
    public static func draft(existing: String, adding text: String) -> String {
        let added = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !added.isEmpty else { return existing }
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? added : existing + "\n\n" + added
    }
}

/// Where a Quick Entry message goes, and the line the sheet shows about it.
public struct QuickEntryDestination: Equatable, Sendable {
    public var target: OutboundTarget
    public var label: String

    public init(target: OutboundTarget, label: String) {
        self.target = target
        self.label = label
    }
}

/// The one place that decides where Quick Entry sends. Change this function to change the behaviour.
public enum QuickEntryPolicy {
    /// Follow up in the chat the user used last; with none yet, start a new chat.
    public static func destination(lastChat: RecentChat?) -> QuickEntryDestination {
        guard let lastChat else { return newChat }
        let title = lastChat.title.isEmpty ? "Untitled chat" : lastChat.title
        return QuickEntryDestination(target: .chat(lastChat.id), label: "Sends to \(title)")
    }

    public static let newChat = QuickEntryDestination(target: .newChat, label: "Sends to a new chat")
}
