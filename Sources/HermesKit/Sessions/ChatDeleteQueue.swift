import Foundation

/// A chat the user deleted that is still inside its Undo window. It is hidden from the list but not deleted yet.
public struct PendingChatDelete: Sendable, Equatable, Identifiable {
    /// The list id: a server session id, or `local-<uuid>` for a local chat.
    public let id: String
    public let title: String
    /// Messages in this chat's outbox that are waiting (pending or failed). They are discarded with the chat. Counted
    /// after the outbox is paused, so it never includes a message already going out.
    public internal(set) var waitingMessages: Int
    /// When the delete happens. Pushed back while VoiceOver focus is on the Undo toast.
    public internal(set) var deadline: Date
    /// True while VoiceOver focus is on the toast: the chat isn't deleted until focus leaves.
    public internal(set) var isHeld = false

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
    public private(set) var committing: Set<String> = []
    /// Chats deleted on the server whose saved messages are still to be cleared. They stay hidden and paused.
    public private(set) var cleanupPending: Set<String> = []

    private var commits: [String: Commit] = [:]
    private let now: () -> Date
    private let pauses: OutboxPauses

    public init(now: @escaping () -> Date = Date.init, pauses: OutboxPauses = .shared) {
        self.now = now
        self.pauses = pauses
    }

    /// Chats the list must not show: pending and committing deletes.
    public var hiddenIDs: Set<String> { committing.union(cleanupPending).union(pending.map(\.id)) }

    /// The delete the toast offers to undo.
    public var latest: PendingChatDelete? { pending.last }

    /// The earliest moment ``tick()`` has work, or nil when nothing is waiting.
    public var nextDeadline: Date? {
        pending.filter { !$0.isHeld }.map(\.deadline).min()
    }

    /// Starts the Undo window for a chat and pauses its outbox. A chat already pending or being deleted is left alone.
    @discardableResult
    public func delete(
        id: String, title: String, waitingMessages: Int = 0, commit: @escaping Commit
    ) -> PendingChatDelete? {
        guard !hiddenIDs.contains(id) else { return nil }
        let item = PendingChatDelete(
            id: id, title: title, waitingMessages: waitingMessages, deadline: now().addingTimeInterval(Self.window))
        pending.append(item)
        commits[id] = commit
        pauses.pause(id)
        return item
    }

    /// Sets the waiting-message count once it is known. The caller counts after ``delete(id:title:waitingMessages:commit:)``
    /// has paused the outbox, so a message that went out first isn't promised as discarded.
    public func setWaitingMessages(_ id: String, _ count: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].waitingMessages = count
    }

    /// Undo: the chat comes back and its outbox may send again. False when the delete is no longer pending.
    @discardableResult
    public func undo(_ id: String) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        commits[id] = nil
        pauses.resume(id)
        return true
    }

    /// The app left the foreground: every pending delete is cancelled and its chat comes back. Deletes already running
    /// finish. Returns the chats that came back.
    @discardableResult
    public func cancelAll() -> [PendingChatDelete] {
        let cancelled = pending
        for item in cancelled { undo(item.id) }
        return cancelled
    }

    /// VoiceOver focus entered (`true`) or left the toast. While held the chat isn't deleted; on release the full window
    /// starts again, so the user has time to act.
    public func hold(_ id: String, _ held: Bool) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].isHeld = held
        if !held { pending[index].deadline = now().addingTimeInterval(Self.window) }
    }

    /// Runs every delete whose window has passed, oldest first. A failed delete brings its chat back and resumes its
    /// outbox; it never disappears silently.
    public func tick() async -> [ChatDeleteOutcome] {
        let time = now()
        let due = pending.filter { !$0.isHeld && $0.deadline <= time }
        var outcomes: [ChatDeleteOutcome] = []
        for item in due {
            guard let commit = commits[item.id] else { continue }
            pending.removeAll { $0.id == item.id }
            commits[item.id] = nil
            committing.insert(item.id)
            do {
                switch try await commit() {
                case .deleted(let discarded):
                    outcomes.append(.deleted(id: item.id, discardedMessages: discarded))
                    pauses.resume(item.id)
                case .deletedCleanupPending:
                    // The server no longer has the chat: it never comes back, and its outbox stays paused so nothing is
                    // submitted to a deleted chat. The launch sweep clears its messages.
                    cleanupPending.insert(item.id)
                    outcomes.append(.deletedCleanupPending(id: item.id))
                }
            } catch {
                outcomes.append(.restored(id: item.id, title: item.title, reason: Self.reason(error)))
                pauses.resume(item.id)
            }
            committing.remove(item.id)
        }
        return outcomes
    }

    private static func reason(_ error: any Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.isEmpty ? "The delete didn't go through." : text
    }
}
