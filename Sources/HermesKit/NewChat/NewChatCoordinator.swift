import Foundation

/// Runs every New chat of the app (board row 104): it makes the durable placeholders, queues a first message in the
/// right one, delivers when the placeholder's own server is connected, brings the placeholders back after a relaunch, and
/// tells the screen when a placeholder has become a server chat. The screen model only maps its answers to rows.
public actor NewChatCoordinator {
    private let placeholders: any PlaceholderStore
    private let outbox: any OutboxStore
    private let creator: @Sendable (_ connectionID: String) -> (any NewChatCreator)?
    private let status: @Sendable (_ connectionID: String) async -> PillState
    private let onCreated: @Sendable (_ placeholder: PlaceholderChat, _ sessionID: String) async -> Void
    private let clock: @Sendable () -> Date
    private var deliveries: [String: NewChatDelivery] = [:]
    private var announced: Set<String> = []

    /// - Parameters:
    ///   - creator: makes sessions on one saved server. Nil when that server is not saved (any more).
    ///   - status: that server's chat status now.
    ///   - onCreated: runs once per placeholder when its session exists and its messages sit under the session id. The
    ///     screen adopts the chat there. The placeholder is forgotten after it returns.
    public init(
        placeholders: any PlaceholderStore, outbox: any OutboxStore,
        creator: @escaping @Sendable (String) -> (any NewChatCreator)?,
        status: @escaping @Sendable (String) async -> PillState,
        onCreated: @escaping @Sendable (PlaceholderChat, String) async -> Void,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.placeholders = placeholders
        self.outbox = outbox
        self.creator = creator
        self.status = status
        self.onCreated = onCreated
        self.clock = clock
    }

    /// A new placeholder bound to one saved server. It is saved before it is returned.
    public func makePlaceholder(connectionID: String, serverName: String) async throws -> PlaceholderChat {
        let chat = PlaceholderChat(connectionID: connectionID, serverName: serverName, createdAt: clock())
        try await placeholders.insert(chat)
        return chat
    }

    /// Saves a placeholder the screen made in memory, if it is not saved yet. An empty placeholder is not saved until
    /// its first message, so the screen can make one without writing anything.
    public func ensureSaved(_ chat: PlaceholderChat) async throws {
        if try await placeholders.placeholder(id: chat.id) == nil { try await placeholders.insert(chat) }
    }

    /// Queues a message in a placeholder and delivers it if its server is connected. The message is saved first.
    @discardableResult
    public func send(_ text: String, in placeholderID: String) async throws -> NewChatState {
        guard let delivery = try await delivery(for: placeholderID) else { return .createFailed(reason: Self.gone) }
        let state = try await delivery.enqueue(text)
        await announceIfCreated(placeholderID, state)
        return state
    }

    /// The user's Retry after a refusal.
    @discardableResult
    public func retry(_ placeholderID: String) async -> NewChatState {
        guard let delivery = try? await delivery(for: placeholderID) else { return .createFailed(reason: Self.gone) }
        let state = await delivery.retry()
        await announceIfCreated(placeholderID, state)
        return state
    }

    /// A server's chat status changed or it connected: every placeholder bound to it tries to deliver, oldest first.
    public func serverMayBeBack(connectionID: String) async {
        guard let all = try? await placeholders.all() else { return }
        for chat in all where chat.connectionID == connectionID {
            guard let delivery = try? await delivery(for: chat.id) else { continue }
            await announceIfCreated(chat.id, await delivery.deliver())
        }
    }

    /// Every placeholder that was saved, for the list after a relaunch. Those with a waiting message try to deliver, so
    /// a message that waited through a relaunch goes out as soon as its server is connected.
    public func restore() async throws -> [PlaceholderChat] {
        let all = try await placeholders.all()
        for chat in all {
            guard let delivery = try await delivery(for: chat.id) else { continue }
            await announceIfCreated(chat.id, await delivery.deliver())
        }
        return try await placeholders.all()
    }

    /// The messages waiting in a placeholder, oldest first, for its "Waiting to send" rows.
    public func waiting(in placeholderID: String) async throws -> [OutboundRecord] {
        guard let chat = try await placeholders.placeholder(id: placeholderID) else { return [] }
        return try await outbox.records(inChat: placeholderID).filter {
            $0.connectionID == chat.connectionID && !$0.state.isSent
        }
    }

    /// The state of a placeholder's delivery, or empty when it has none yet.
    public func state(of placeholderID: String) async -> NewChatState {
        guard let delivery = deliveries[placeholderID] else { return .empty }
        return await delivery.state
    }

    private static let gone = "This server is no longer saved."

    private func delivery(for placeholderID: String) async throws -> NewChatDelivery? {
        if let existing = deliveries[placeholderID] { return existing }
        guard let chat = try await placeholders.placeholder(id: placeholderID),
            let creator = creator(chat.connectionID)
        else { return nil }
        let connectionID = chat.connectionID
        let status = status
        let made = NewChatDelivery(
            placeholder: chat, placeholders: placeholders, outbox: outbox, creator: creator,
            status: { await status(connectionID) }, clock: clock)
        deliveries[placeholderID] = made
        return made
    }

    /// Hands a created chat to the screen once, then forgets the placeholder.
    private func announceIfCreated(_ placeholderID: String, _ state: NewChatState) async {
        guard case .created(let sessionID) = state, !announced.contains(placeholderID),
            let chat = try? await placeholders.placeholder(id: placeholderID)
        else { return }
        announced.insert(placeholderID)
        await onCreated(chat, sessionID)
        try? await placeholders.remove(id: placeholderID)
        deliveries[placeholderID] = nil
    }
}
