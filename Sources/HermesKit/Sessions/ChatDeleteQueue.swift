import Foundation

/// One chat on one server. Two servers can have a chat with the same id, so the delete queue keys by both (row 99).
public struct ChatDeleteKey: Hashable, Sendable {
    /// The saved server, or nil for a local chat.
    public let connection: String?
    public let chatID: String

    public init(connection: String?, chatID: String) {
        self.connection = connection
        self.chatID = chatID
    }
}

/// A chat the user deleted that is still inside its Undo window. It is hidden from the list but not deleted yet.
public struct PendingChatDelete: Sendable, Equatable, Identifiable {
    /// The list id: a server session id, or `local-<uuid>` for a local chat.
    public let id: String
    /// The chat's server, or nil for a local chat.
    public let connection: String?
    public let title: String
    /// Messages in this chat's outbox that are waiting (pending or failed). They are discarded with the chat. Counted
    /// after the outbox is paused, so it never includes a message already going out.
    public internal(set) var waitingMessages: Int
    /// When the delete happens. Pushed back while VoiceOver focus is on the Undo toast.
    public internal(set) var deadline: Date
    /// True while VoiceOver focus is on the toast: the chat isn't deleted until focus leaves.
    public internal(set) var isHeld = false

    public var key: ChatDeleteKey { ChatDeleteKey(connection: connection, chatID: id) }

    /// The toast text: "Chat deleted", plus how many waiting messages go with it.
    public var message: String {
        switch waitingMessages {
        case 0: "Chat deleted"
        case 1: "Chat deleted · 1 waiting message discarded"
        default: "Chat deleted · \(waitingMessages) waiting messages discarded"
        }
    }

    /// What VoiceOver says when the toast appears.
    public var announcement: String {
        waitingMessages == 0
            ? "Chat deleted. Undo available."
            : "\(message.replacingOccurrences(of: " · ", with: ". ")). Undo available."
    }
}

/// What a commit did. A commit throws only when the chat still exists (the server delete failed).
public enum ChatDeleteCommit: Sendable, Equatable {
    /// The chat and its waiting messages are gone.
    case deleted(discardedMessages: Int)
    /// The server deleted the chat, but its saved messages couldn't be cleared yet. They are cleared at the next launch.
    case deletedCleanupPending
}

/// How a pending delete ended.
public enum ChatDeleteOutcome: Sendable, Equatable {
    /// The chat is gone, with the waiting messages that went with it.
    case deleted(id: String, discardedMessages: Int)
    /// The chat is gone from the server, but its saved messages are cleared at the next launch. It stays hidden and
    /// its outbox stays paused, so nothing is sent to a deleted chat.
    case deletedCleanupPending(id: String)
    /// The delete failed, so the chat is back in the list. The reason is for the user.
    case restored(id: String, title: String, reason: String)
}

/// Undo for chat delete, for server and local chats alike. Delete hides the chat and pauses its outbox; after
/// ``window`` seconds ``tick()`` runs the real delete. Undo, or the app leaving the foreground, puts the chat back
/// untouched. Nothing is stored, so a killed app deletes nothing.
///
/// The clock is injected and the caller drives ``tick()``, so tests need no timers.
@MainActor
public final class ChatDeleteQueue {
    /// Deletes the chat and its waiting messages. Throw only when the chat still exists, which brings it back; once the
    /// server delete has succeeded, return ``ChatDeleteCommit/deletedCleanupPending`` instead of throwing.
    public typealias Commit = @MainActor () async throws -> ChatDeleteCommit

    /// How long Undo stays available.
    public static let window: TimeInterval = 5

    /// Pending deletes, oldest first. The toast shows the last one.
    public private(set) var pending: [PendingChatDelete] = []
    /// Chats whose delete is running now. They stay hidden until it finishes.
    public private(set) var committing: Set<ChatDeleteKey> = []
    /// Chats deleted on the server whose saved messages are still to be cleared. They stay hidden and paused.
    public private(set) var cleanupPending: Set<ChatDeleteKey> = []

    private var commits: [ChatDeleteKey: Commit] = [:]
    private let now: () -> Date
    private let pauses: OutboxPauses

    public init(now: @escaping () -> Date = Date.init, pauses: OutboxPauses = .shared) {
        self.now = now
        self.pauses = pauses
    }

    /// Chats the list must not show: pending and committing deletes.
    public var hiddenKeys: Set<ChatDeleteKey> { committing.union(cleanupPending).union(pending.map(\.key)) }

    /// The chat ids of ``hiddenKeys``, for lists that show one server's chats.
    public var hiddenIDs: Set<String> { Set(hiddenKeys.map(\.chatID)) }

    /// The delete the toast offers to undo.
    public var latest: PendingChatDelete? { pending.last }

    /// The earliest moment ``tick()`` has work, or nil when nothing is waiting.
    public var nextDeadline: Date? {
        pending.filter { !$0.isHeld }.map(\.deadline).min()
    }

    /// Starts the Undo window for a chat and pauses its outbox. A chat already pending or being deleted is left alone.
    @discardableResult
    public func delete(
        id: String, title: String, connection: String? = nil, waitingMessages: Int = 0, commit: @escaping Commit
    ) -> PendingChatDelete? {
        let key = ChatDeleteKey(connection: connection, chatID: id)
        // The same chat id on another server is a different chat: only this server's copy is checked (review m1).
        guard !hiddenKeys.contains(key) else { return nil }
        let item = PendingChatDelete(
            id: id, connection: connection, title: title, waitingMessages: waitingMessages,
            deadline: now().addingTimeInterval(Self.window))
        pending.append(item)
        commits[key] = commit
        pauses.pause(id, connection: connection)
        return item
    }

    /// Sets the waiting-message count once it is known. The caller counts after ``delete(id:title:waitingMessages:commit:)``
    /// has paused the outbox, so a message that went out first isn't promised as discarded.
    public func setWaitingMessages(_ id: String, _ count: Int, connection: String? = nil) {
        let key = ChatDeleteKey(connection: connection, chatID: id)
        guard let index = pending.firstIndex(where: { $0.key == key }) else { return }
        pending[index].waitingMessages = count
    }

    /// Undo: the chat comes back and its outbox may send again. False when the delete is no longer pending.
    @discardableResult
    public func undo(_ id: String, connection: String? = nil) -> Bool {
        let key = ChatDeleteKey(connection: connection, chatID: id)
        guard let index = pending.firstIndex(where: { $0.key == key }) else { return false }
        pending.remove(at: index)
        commits[key] = nil
        resume(key)
        return true
    }

    /// The app left the foreground: every pending delete is cancelled and its chat comes back. Deletes already running
    /// finish. Returns the chats that came back.
    @discardableResult
    public func cancelAll() -> [PendingChatDelete] {
        let cancelled = pending
        for item in cancelled { undo(item.id, connection: item.connection) }
        return cancelled
    }

    /// VoiceOver focus entered (`true`) or left the toast. While held the chat isn't deleted; on release the full window
    /// starts again, so the user has time to act.
    public func hold(_ id: String, _ held: Bool, connection: String? = nil) {
        let key = ChatDeleteKey(connection: connection, chatID: id)
        guard let index = pending.firstIndex(where: { $0.key == key }) else { return }
        pending[index].isHeld = held
        if !held { pending[index].deadline = now().addingTimeInterval(Self.window) }
    }

    /// Lifts this queue's pause on a chat, for the same server it paused.
    private func resume(_ key: ChatDeleteKey) {
        pauses.resume(key.chatID, connection: key.connection)
    }

    /// Runs every delete whose window has passed, oldest first. A failed delete brings its chat back and resumes its
    /// outbox; it never disappears silently.
    public func tick() async -> [ChatDeleteOutcome] {
        let time = now()
        let due = pending.filter { !$0.isHeld && $0.deadline <= time }
        var outcomes: [ChatDeleteOutcome] = []
        for item in due {
            let key = item.key
            guard let commit = commits[key] else { continue }
            pending.removeAll { $0.key == key }
            commits[key] = nil
            committing.insert(key)
            do {
                switch try await commit() {
                case .deleted(let discarded):
                    outcomes.append(.deleted(id: item.id, discardedMessages: discarded))
                    resume(key)
                case .deletedCleanupPending:
                    // The server no longer has the chat: it never comes back, and its outbox stays paused so nothing is
                    // submitted to a deleted chat. The launch sweep clears its messages.
                    cleanupPending.insert(key)
                    outcomes.append(.deletedCleanupPending(id: item.id))
                }
            } catch {
                outcomes.append(.restored(id: item.id, title: item.title, reason: Self.reason(error)))
                resume(key)
            }
            committing.remove(key)
        }
        return outcomes
    }

    private static func reason(_ error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.isEmpty ? "The delete didn't go through." : text
    }
}

/// A server chat's delete after its Undo window (row 99 n1): the server deletes the chat, a tombstone is written at
/// once, then this server's waiting messages for the chat are purged, tried twice. A purge that still fails leaves the
/// tombstone for the launch sweep (``OutboxTombstones/sweep(store:)``) and reports the cleanup as pending.
///
/// It throws only when the server delete fails: then nothing is tombstoned or purged, and the chat comes back.
public enum ServerChatDelete {
    public static func commit(
        chatID: String, connection: String, tombstones: OutboxTombstones,
        deleteOnServer: () async throws -> Void, purge: () async throws -> Int
    ) async throws -> ChatDeleteCommit {
        try await deleteOnServer()
        let entry = OutboxTombstones.Entry(connection: connection, chatID: chatID)
        tombstones.add(entry)
        for _ in 0..<2 {
            if let discarded = try? await purge() {
                tombstones.remove(entry)
                return .deleted(discardedMessages: discarded)
            }
        }
        return .deletedCleanupPending
    }
}
