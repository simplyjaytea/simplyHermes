import Foundation

// Local notifications for a finished reply and a waiting approval (spec:
// Shared/simplyhermes-notifications-spec-2026-11-12.md). The rules live here, without UIKit, so Linux tests cover
// them. The app turns ``NotificationAction``s into `UNUserNotificationCenter` calls. A push relay, if it ever comes,
// sends the same ``NotificationRequest`` shape, and the shared ``NotificationRequest/dedupeKey`` keeps one copy.

/// The user's notification settings (Settings › Notifications).
public struct NotificationPreferences: Sendable, Equatable {
    /// "Reply finished", including a turn that ended in an error.
    public var replyFinished: Bool
    /// "Approval waiting".
    public var approvalWaiting: Bool
    /// Show the chat title and the reply or command. Off by default: the Lock Screen is not private.
    public var showContent: Bool
    /// The quick-action privacy setting "Show chat title". Off hides the title even with content on.
    public var showChatTitle: Bool
    /// Play the app's turn-done and approval sounds.
    public var sound: Bool

    public init(
        replyFinished: Bool = true, approvalWaiting: Bool = true, showContent: Bool = false,
        showChatTitle: Bool = true, sound: Bool = true
    ) {
        self.replyFinished = replyFinished
        self.approvalWaiting = approvalWaiting
        self.showContent = showContent
        self.showChatTitle = showChatTitle
        self.sound = sound
    }

    public static let replyFinishedKey = "notifications.replyFinished"
    public static let approvalWaitingKey = "notifications.approvalWaiting"
    public static let showContentKey = "notifications.showContent"
    public static let soundKey = "notifications.sound"

    /// Reads the settings; a key never set keeps its default. `showChatTitle` comes from the quick-action setting.
    public static func load(from defaults: UserDefaults, showChatTitle: Bool = true) -> NotificationPreferences {
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        return NotificationPreferences(
            replyFinished: flag(replyFinishedKey, true), approvalWaiting: flag(approvalWaitingKey, true),
            showContent: flag(showContentKey, false), showChatTitle: showChatTitle, sound: flag(soundKey, true))
    }

    /// Writes the settings this type owns (not `showChatTitle`).
    public func save(to defaults: UserDefaults) {
        defaults.set(replyFinished, forKey: Self.replyFinishedKey)
        defaults.set(approvalWaiting, forKey: Self.approvalWaitingKey)
        defaults.set(showContent, forKey: Self.showContentKey)
        defaults.set(sound, forKey: Self.soundKey)
    }
}

/// Which chat an event belongs to, as the notification names it.
public struct NotificationChat: Sendable, Equatable {
    public var id: String
    public var title: String
    /// The server's name, or nil for a local chat (answered on this iPhone).
    public var serverName: String?

    public init(id: String, title: String, serverName: String?) {
        self.id = id
        self.title = title
        self.serverName = serverName
    }

    public var isLocal: Bool { serverName == nil }
}

/// Something that may deserve a notification.
public enum NotificationEvent: Sendable, Equatable {
    /// How a turn ended.
    public enum Outcome: Sendable, Equatable {
        case done
        case failed
        /// The user stopped it, so there is nothing to tell.
        case stopped
    }

    /// A turn ended. `turnID` names the turn the same way every time it is seen (its reply's row id), so a replay
    /// notifies once. `reply` is that turn's own reply text (Markdown), or "" when it has none.
    case turnEnded(NotificationChat, turnID: String, startedAt: Date, endedAt: Date, outcome: Outcome, reply: String)
    /// An approval started waiting.
    case approvalWaiting(NotificationChat, requestID: String, command: String)
    /// An approval was answered or withdrawn, here or anywhere else.
    case approvalResolved(chatID: String, requestID: String)
}

/// Where the user is when the event happens.
public struct NotificationContext: Sendable, Equatable {
    /// The app is in the foreground and its window is in use.
    public var appIsActive: Bool
    /// The chat on screen, if any.
    public var chatOnScreen: String?
    /// More than one server is saved, so a notification names its server.
    public var multipleServers: Bool
    public var now: Date

    public init(appIsActive: Bool, chatOnScreen: String?, multipleServers: Bool, now: Date) {
        self.appIsActive = appIsActive
        self.chatOnScreen = chatOnScreen
        self.multipleServers = multipleServers
        self.now = now
    }
}

/// One notification to show.
public struct NotificationRequest: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case reply
        case approval
    }

    /// The system identifier. A chat's reply notification replaces its earlier one; each approval has its own.
    public var id: String
    /// Groups a chat's notifications (`threadIdentifier`).
    public var threadID: String
    /// The chat a tap opens.
    public var chatID: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var playsSound: Bool
    /// The same event always has the same key, local or pushed.
    public var dedupeKey: String
}

/// What to do with the system's notifications.
public enum NotificationAction: Sendable, Equatable {
    case post(NotificationRequest)
    /// Remove delivered or pending notifications with these identifiers.
    case remove([String])
}

/// Decides which notifications to post or remove. It remembers what it posted, so an event seen again (a reconnect
/// that replays the turn, the monitor noticing the same change twice) posts nothing new.
public struct NotificationPlanner: Sendable {
    /// A reply that finished longer ago than this when the app learns of it is not news anymore.
    public static let staleAfter: TimeInterval = 10 * 60
    /// Characters of a reply line or a command in the body.
    public static let bodyLimit = 120
    public static let hiddenBody = "Open simplyHermes to see it."

    private var seen: Set<String> = []

    public init() {}

    public mutating func plan(
        _ event: NotificationEvent, context: NotificationContext, preferences: NotificationPreferences
    ) -> [NotificationAction] {
        switch event {
        case .approvalResolved(let chatID, let requestID):
            return [.remove([Self.approvalID(chatID: chatID, requestID: requestID)])]

        case .approvalWaiting(let chat, let requestID, let command):
            let key = "\(chat.id):approval:\(requestID)"
            guard preferences.approvalWaiting, !isSeen(key), Self.shouldTell(chat.id, context) else { return [] }
            return [
                .post(
                    request(
                        Draft(
                            kind: .approval, chat: chat, key: key,
                            id: Self.approvalID(chatID: chat.id, requestID: requestID),
                            headline: "Hermes needs your OK", detail: command),
                        context, preferences))
            ]

        case .turnEnded(let chat, let turnID, _, let endedAt, let outcome, let reply):
            let key = "\(chat.id):turn:\(turnID)"
            guard outcome != .stopped, preferences.replyFinished, !isSeen(key), Self.shouldTell(chat.id, context),
                context.now.timeIntervalSince(endedAt) <= Self.staleAfter
            else { return [] }
            let headline = outcome == .failed ? "Hermes stopped with an error" : "Hermes replied"
            return [
                .post(
                    request(
                        Draft(
                            kind: .reply, chat: chat, key: key, id: "reply.\(chat.id)", headline: headline,
                            detail: outcome == .failed ? "" : reply),
                        context, preferences))
            ]
        }
    }

    /// Marks `key` seen and says whether it was already.
    private mutating func isSeen(_ key: String) -> Bool {
        !seen.insert(key).inserted
    }

    /// Not for the chat the user is looking at in the active app: that chat already plays its sound.
    static func shouldTell(_ chatID: String, _ context: NotificationContext) -> Bool {
        !(context.appIsActive && context.chatOnScreen == chatID)
    }

    static func approvalID(chatID: String, requestID: String) -> String {
        "approval.\(chatID).\(requestID)"
    }

    /// One notification before its text is decided.
    private struct Draft {
        var kind: NotificationRequest.Kind
        var chat: NotificationChat
        var key: String
        var id: String
        var headline: String
        var detail: String
    }

    private typealias Prefs = NotificationPreferences

    private func request(_ draft: Draft, _ context: NotificationContext, _ preferences: Prefs) -> NotificationRequest {
        let (kind, chat, key, id, headline, detail) = (
            draft.kind, draft.chat, draft.key, draft.id, draft.headline, draft.detail
        )
        let title: String
        let body: String
        if preferences.showContent {
            let name = preferences.showChatTitle ? Self.trimmedTitle(chat.title) : "a chat"
            var place = ""
            if chat.isLocal {
                place = " · On this iPhone"
            } else if context.multipleServers, let server = chat.serverName {
                place = " on \(server)"
            }
            title = "\(headline): \(name)\(place)"
            let line = kind == .approval ? Self.cut(Self.firstLine(detail)) : Self.cut(Self.plainFirstLine(detail))
            body = line.isEmpty ? Self.hiddenBody : line
        } else {
            title = headline
            body = Self.hiddenBody
        }
        return NotificationRequest(
            id: id, threadID: chat.id, chatID: chat.id, kind: kind, title: title, body: body,
            playsSound: preferences.sound, dedupeKey: key)
    }

    static func trimmedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "a chat" : trimmed
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// The first line of prose of a Markdown reply: code fences are skipped, and heading, quote and list marks and
    /// emphasis are removed.
    static func plainFirstLine(_ markdown: String) -> String {
        var inFence = false
        for raw in markdown.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || line.isEmpty { continue }
            while let first = line.first, "#>".contains(first) {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
                line = String(line.dropFirst(2))
            }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
            if !line.isEmpty { return line }
        }
        return ""
    }

    static func cut(_ text: String) -> String {
        guard text.count > bodyLimit else { return text }
        return String(text.prefix(bodyLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
