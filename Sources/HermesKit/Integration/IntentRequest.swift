import Foundation

/// What an App Intent, Siri phrase, Control Center control or the Action button asks the app to do.
///
/// Intents only describe the request. The app turns it into work, because only the app holds the connection to the
/// server. Keeping the mapping here means it is tested without a device.
public enum IntentRequest: Equatable, Sendable {
    /// Send `text` to `chatID`, or to the chat used last when `chatID` is `nil`.
    case ask(text: String, chatID: String?)
    /// Work as `bot` (a Hermes profile), start a new chat and send `text` there.
    case askBot(bot: String, text: String)
    /// Start a new chat. With `text`, send it as the first message.
    case newChat(text: String?)
    case stopAll
    case approvePending
    case openQuickEntry(prefill: String?)
}

public enum IntentMappingError: Error, Equatable, Sendable {
    case emptyMessage
    case missingBot

    /// What Siri says.
    public var dialog: String {
        switch self {
        case .emptyMessage: "There is nothing to send."
        case .missingBot: "Choose a bot first."
        }
    }

    /// What Siri says for an error caught from the mapping functions, which throw this type.
    public static func dialog(for error: any Error) -> String {
        (error as? IntentMappingError)?.dialog ?? IntentOutcome.needsApp.dialog
    }
}

/// Turns the parameters of an intent into an ``IntentRequest``.
public enum IntentMapping {
    /// Longest message an intent sends, in characters.
    public static let maxMessageCharacters = 20_000

    public static func ask(text: String, chatID: String?) throws(IntentMappingError) -> IntentRequest {
        let message = clean(text)
        guard !message.isEmpty else { throw IntentMappingError.emptyMessage }
        return .ask(text: message, chatID: nonBlank(chatID))
    }

    public static func askBot(bot: String, text: String) throws(IntentMappingError) -> IntentRequest {
        guard let name = nonBlank(bot) else { throw IntentMappingError.missingBot }
        let message = clean(text)
        guard !message.isEmpty else { throw IntentMappingError.emptyMessage }
        return .askBot(bot: name, text: message)
    }

    /// A blank first message means "just open a new chat".
    public static func newChat(text: String?) -> IntentRequest {
        let message = text.map(clean) ?? ""
        return .newChat(text: message.isEmpty ? nil : message)
    }

    public static func quickEntry(prefill: String?) -> IntentRequest {
        let text = prefill.map(clean) ?? ""
        return .openQuickEntry(prefill: text.isEmpty ? nil : text)
    }

    /// The message a request sends, or `nil` for requests that only act.
    public static func message(
        for request: IntentRequest, id: String = UUID().uuidString, now: Date
    ) -> OutboundMessage? {
        switch request {
        case .ask(let text, let chatID):
            let target: OutboundTarget = chatID.map(OutboundTarget.chat) ?? .lastUsed
            return OutboundMessage(id: id, text: text, target: target, createdAt: now)
        case .askBot(_, let text):
            return OutboundMessage(id: id, text: text, target: .newChat, createdAt: now)
        case .newChat(let text):
            guard let text else { return nil }
            return OutboundMessage(id: id, text: text, target: .newChat, createdAt: now)
        case .stopAll, .approvePending, .openQuickEntry:
            return nil
        }
    }

    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxMessageCharacters ? String(trimmed.prefix(maxMessageCharacters)) : trimmed
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// An approval a chat waits on, as the "Approve pending" intent sees it.
public struct PendingApprovalRef: Equatable, Sendable {
    public var sessionID: String
    public var chatTitle: String
    public var command: String

    public init(sessionID: String, chatTitle: String, command: String) {
        self.sessionID = sessionID
        self.chatTitle = chatTitle
        self.command = command
    }
}

public enum ApprovalPick: Equatable, Sendable {
    case approve(PendingApprovalRef)
    case nothing
    case several(count: Int)
}

/// "Approve pending" approves a command, so it acts only when there is no doubt which one.
public enum ApprovalPicker {
    public static func pick(_ pending: [PendingApprovalRef]) -> ApprovalPick {
        switch pending.count {
        case 0: .nothing
        case 1: .approve(pending[0])
        default: .several(count: pending.count)
        }
    }
}

/// What happened, as the app reports it back to the intent.
public enum IntentOutcome: Equatable, Sendable {
    /// The message is on its way. `chatTitle` is `nil` when it goes to a new chat.
    case queued(chatTitle: String?)
    /// The message goes to a new chat that works as the named bot.
    case askedBot(name: String)
    case openedNewChat
    case openedQuickEntry
    case stopped(count: Int)
    case nothingRunning
    case approved(command: String)
    case nothingToApprove
    case severalToApprove(count: Int)
    case unknownBot(String)
    /// No server is connected, so the request could not be carried out.
    case notConnected
    /// A server is saved, but it did not make the new chat.
    case couldNotStartChat
    /// The app was not reachable, so the request was not carried out.
    case needsApp

    /// The sentence Siri and Shortcuts show or speak.
    public var dialog: String {
        switch self {
        case .queued(let title?): "Sending to \(title)."
        case .queued(nil): "Sending to a new chat."
        case .askedBot(let name): "Asking \(name)."
        case .openedNewChat: "Started a new chat."
        case .openedQuickEntry: "Opening Quick Entry."
        case .stopped(let count): count == 1 ? "Stopped 1 turn." : "Stopped \(count) turns."
        case .nothingRunning: "Nothing is running."
        case .approved(let command): "Approved: \(LiveTurnState.cut(command, to: 80))"
        case .nothingToApprove: "Nothing is waiting for approval."
        case .severalToApprove(let count): "\(count) approvals are waiting. Open simplyHermes to choose which."
        case .unknownBot(let name): "I could not find a bot called \(name)."
        case .notConnected: "simplyHermes is not connected to a server. Open it to connect, then try again."
        case .couldNotStartChat: "I could not start a new chat. Open simplyHermes to check the server, then try again."
        case .needsApp: "Open simplyHermes to continue."
        }
    }

    /// The outcome of stopping `count` turns.
    public static func afterStopping(_ count: Int) -> IntentOutcome {
        count == 0 ? .nothingRunning : .stopped(count: count)
    }
}
