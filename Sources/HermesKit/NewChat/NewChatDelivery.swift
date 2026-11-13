import Foundation

/// Makes the server session for a New chat.
public protocol NewChatCreator: Sendable {
    /// Creates an empty chat on the server and returns its session id.
    /// - Throws: ``NewChatCreateError``. Any other error counts as the server being unreachable.
    func createSession() async throws -> String
}

/// Why a session could not be created.
public enum NewChatCreateError: Error, Sendable, Equatable {
    /// The server answered and said no (a missing profile, for example). The reason is the server's, in plain text.
    case refused(String)
    /// The connection was lost or never made. Nothing reached the server's decision, so the message keeps waiting.
    case unreachable
}

/// Where a New chat is on its way to becoming a server chat.
public enum NewChatState: Sendable, Equatable {
    /// Nothing sent yet.
    case empty
    /// The first message is saved and waits for its server to be connected.
    case waitingForServer
    /// The server is connected and the session is being made.
    case creatingChat
    /// The session exists and the waiting messages are under its id. The chat is a server chat from here.
    case created(sessionID: String)
    /// The server refused to make the chat. The messages are kept as failed, for Retry, Edit or Delete.
    case createFailed(reason: String)
}

/// Delivers a New chat's first message: it saves the message, waits for the chat's own server, makes the session once,
/// and moves the waiting messages to it, where the chat's normal drainer sends them (board row 104, WP-8).
///
/// - Never lost: the message is in the outbox before anything else is tried, and the session id is saved before the
///   messages move.
/// - Sent once: one session per placeholder, even with several triggers at once, and a saved session id is reused after
///   a relaunch.
/// - Never sent while the server is down: nothing is created unless the server's status is `.connected`.
/// - Bound to its server: it uses its own creator and status and moves only records of its own connection.
public actor NewChatDelivery {
    public private(set) var state: NewChatState = .empty

    private let placeholder: PlaceholderChat
    private let placeholders: any PlaceholderStore
    private let outbox: any OutboxStore
    private let creator: any NewChatCreator
    private let status: @Sendable () async -> PillState
    private let clock: @Sendable () -> Date
    private var isRunning = false

    /// - Parameters:
    ///   - status: the bound server's chat status now. Only `.connected` lets anything go out.
    public init(
        placeholder: PlaceholderChat, placeholders: any PlaceholderStore, outbox: any OutboxStore,
        creator: any NewChatCreator, status: @escaping @Sendable () async -> PillState,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.placeholder = placeholder
        self.placeholders = placeholders
        self.outbox = outbox
        self.creator = creator
        self.status = status
        self.clock = clock
    }

    /// Saves a message of this chat, then tries to deliver. The message is written first, so a crash at any later step
    /// leaves it waiting. Returns the state after the attempt.
    @discardableResult
    public func enqueue(_ text: String) async throws -> NewChatState {
        try await outbox.insert(
            OutboundRecord(
                connectionID: placeholder.connectionID, chatID: placeholder.id, text: text, createdAt: clock()))
        if state == .empty { state = .waitingForServer }
        return await deliver()
    }

    /// Makes the session and moves the waiting messages once the server is connected. Safe to call from every trigger:
    /// a call while another runs returns the current state and does nothing of its own.
    @discardableResult
    public func deliver() async -> NewChatState {
        if case .created = state { return state }
        guard !isRunning else { return state }
        isRunning = true
        defer { isRunning = false }
        do {
            // A session saved by an earlier run: move the messages, never make a second session.
            if let saved = try await placeholders.placeholder(id: placeholder.id)?.sessionID {
                try await moveMessages(to: saved)
                return state
            }
            // An empty placeholder makes no session: a chat the user has not written in stays a placeholder.
            let waiting = try await outbox.records(inChat: placeholder.id).filter {
                $0.connectionID == placeholder.connectionID && $0.state.kind == .pending
            }
            guard !waiting.isEmpty else { return state }
            guard await status() == .connected else {
                state = .waitingForServer
                return state
            }
            state = .creatingChat
            let sessionID: String
            do {
                sessionID = try await creator.createSession()
            } catch NewChatCreateError.refused(let reason) {
                try await failWaiting(reason: reason)
                return state
            } catch {
                // A lost connection is not the server's answer. The messages keep waiting.
                state = .waitingForServer
                return state
            }
            // Saved before the messages move, so a crash between the two never makes a second session.
            try await placeholders.setSessionID(sessionID, forPlaceholder: placeholder.id)
            try await moveMessages(to: sessionID)
        } catch {
            // The stores failed. Everything written so far is still there, so the next trigger tries again.
            state = .waitingForServer
        }
        return state
    }

    /// The user's Retry after a refusal: the failed messages wait again, then delivery runs.
    @discardableResult
    public func retry() async -> NewChatState {
        guard case .createFailed = state else { return state }
        do {
            for record in try await outbox.records(inChat: placeholder.id)
            where record.connectionID == placeholder.connectionID && record.state.kind == .failed {
                try await outbox.updateState(.pending, forID: record.id, ifCurrently: .failed)
            }
        } catch {
            return state
        }
        state = .waitingForServer
        return await deliver()
    }

    private func moveMessages(to sessionID: String) async throws {
        try await outbox.rebind(chat: placeholder.id, to: sessionID, connection: placeholder.connectionID)
        state = .created(sessionID: sessionID)
    }

    /// The server refused the create. The messages stay, as failed, so the user can retry, edit or delete them.
    private func failWaiting(reason: String) async throws {
        let shown = "Couldn't start the chat on \(placeholder.serverName). \(reason)"
        for record in try await outbox.records(inChat: placeholder.id)
        where record.connectionID == placeholder.connectionID && record.state.kind == .pending {
            try await outbox.updateState(.failed(reason: shown), forID: record.id)
        }
        state = .createFailed(reason: shown)
    }
}
