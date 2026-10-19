import Foundation

/// Why the last offline reply did not arrive.
public enum OfflineReplyFailure: Sendable, Equatable {
    /// The on-device model cannot answer, for this reason.
    case unavailable(LocalModelUnavailable)
    /// The model failed or answered with nothing.
    case modelFailed
    /// The message could not be saved.
    case notSaved
}

/// What the offline chat of one server chat holds now.
public struct OfflineChatSnapshot: Sendable, Equatable {
    /// The open chat. Nil until the user writes the first offline message, and again after the chat is closed.
    public var chat: OfflineChat?
    /// Its messages, oldest first.
    public var messages: [OfflineChatMessage]
    /// True while the on-device model works on a reply.
    public var isReplying: Bool
    /// Why the last reply failed, if it did.
    public var failure: OfflineReplyFailure?

    /// Creates a snapshot. The default is an empty chat.
    public init(
        chat: OfflineChat? = nil, messages: [OfflineChatMessage] = [], isReplying: Bool = false,
        failure: OfflineReplyFailure? = nil
    ) {
        self.chat = chat
        self.messages = messages
        self.isReplying = isReplying
        self.failure = failure
    }
}

/// The offline chat that sits beside one server chat (plan Q44): saves what the user writes while the server is out
/// of reach, asks the on-device model for the reply and saves that too. Nothing here talks to the server, so an offline
/// reply can never end up in the server session. The user's last prompt goes back to Hermes only through
/// ``SendToHermes``, when the user asks for it.
///
/// Prompts are answered one at a time, in the order they were written.
public actor OfflineChatController {
    /// Characters of earlier chat sent along with a new prompt. The on-device model has a small context window.
    public static let historyLimit = 6000

    /// What the model is told about its situation.
    public static let instructions = """
        You are the assistant inside simplyHermes on the user's iPhone. The iPhone cannot reach the Hermes server \
        right now, so you have no tools, no files, no terminal and no internet. Answer from what you know, in a few \
        short sentences. If the task needs the server or a tool, say it has to wait until Hermes is reachable again.
        """

    private let store: any OfflineChatStore
    private let executor: @Sendable () -> any LocalModelExecutor
    private let connection: String
    private let sessionID: String
    private let now: @Sendable () -> Date

    private var chat: OfflineChat?
    private var messages: [OfflineChatMessage] = []
    private var unanswered: [OfflineChatMessage] = []
    private var isReplying = false
    private var failure: OfflineReplyFailure?
    private var subscribers: [UUID: AsyncStream<OfflineChatSnapshot>.Continuation] = [:]

    /// Opens the offline chat of the server chat `sessionID` on `connection`, with the messages saved earlier.
    /// `executor` is asked for the model on every reply, so a model chosen in Settings applies at once.
    public init(
        store: any OfflineChatStore, executor: @escaping @Sendable () -> any LocalModelExecutor, connection: String,
        sessionID: String, now: @escaping @Sendable () -> Date = { Date() }
    ) async {
        self.store = store
        self.executor = executor
        self.connection = connection
        self.sessionID = sessionID
        self.now = now
        if let open = try? await store.currentChat(forSession: sessionID, connection: connection) {
            chat = open
            messages = (try? await store.messages(inChat: open.id, connection: connection)) ?? []
        }
    }

    /// The chat as it is now.
    public var snapshot: OfflineChatSnapshot {
        OfflineChatSnapshot(chat: chat, messages: messages, isReplying: isReplying && chat != nil, failure: failure)
    }

    /// A stream of the chat, starting with the current value and yielding after every change.
    public func states() -> AsyncStream<OfflineChatSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<OfflineChatSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        return stream
    }

    /// Saves `text` as the user's message and has the on-device model answer it. Blank text is ignored. A message
    /// written while the model is still busy waits its turn.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        failure = nil
        let prompt: OfflineChatMessage
        do {
            let current = try await openChat(startingWith: trimmed)
            prompt = try await store.append(
                .user, text: trimmed, toChat: current.id, connection: connection, at: now())
        } catch {
            failure = .notSaved
            publish()
            return
        }
        guard chat?.id == prompt.chatID else { return }
        messages.append(prompt)
        unanswered.append(prompt)
        publish()
        guard !isReplying else { return }
        isReplying = true
        publish()
        while !unanswered.isEmpty {
            await answer(unanswered.removeFirst())
        }
        isReplying = false
        publish()
    }

    /// Closes the chat after the user answered the "Send to Hermes" offer. The next offline message starts a new chat.
    /// A reply that is still on its way is dropped.
    public func resolve(_ resolution: OfflineChat.Resolution) async {
        guard let current = chat else { return }
        chat = nil
        messages = []
        unanswered = []
        failure = nil
        publish()
        try? await store.resolve(chat: current.id, connection: connection, as: resolution, at: now())
    }

    // MARK: - Replies

    private func openChat(startingWith prompt: String) async throws -> OfflineChat {
        if let chat { return chat }
        let started = try await store.openChat(
            forSession: sessionID, connection: connection, title: OfflineChat.title(forPrompt: prompt), at: now())
        chat = started
        return started
    }

    private func answer(_ prompt: OfflineChatMessage) async {
        let model = executor()
        if case .unavailable(let reason) = model.availability {
            failure = .unavailable(reason)
            publish()
            return
        }
        // The chat so far, without this prompt and without prompts that still wait for their turn.
        let waiting = Set(unanswered.map(\.id))
        let history = messages.filter { $0.id != prompt.id && !waiting.contains($0.id) }
        let reply = try? await model.respond(
            instructions: Self.instructions, prompt: Self.prompt(history: history, message: prompt.text))
        // The chat was closed while the model worked: the reply has nowhere to go.
        guard chat?.id == prompt.chatID else { return }
        let text = reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            failure = .modelFailed
            publish()
            return
        }
        do {
            let saved = try await store.append(
                .assistant, text: text, toChat: prompt.chatID, connection: connection, at: now())
            guard chat?.id == prompt.chatID else { return }
            messages.append(saved)
            failure = nil
        } catch OfflineChatError.chatClosed {
            return
        } catch {
            failure = .notSaved
        }
        publish()
    }

    /// The text sent to the model: as much of the chat so far as fits in ``historyLimit`` (the newest turns win),
    /// then the new message.
    static func prompt(history: [OfflineChatMessage], message: String, limit: Int = historyLimit) -> String {
        var lines: [String] = []
        var used = 0
        for entry in history.reversed() {
            let line = "\(entry.role == .user ? "User" : "Assistant"): \(entry.text)"
            if used + line.count > limit { break }
            used += line.count
            lines.append(line)
        }
        guard !lines.isEmpty else { return message }
        return "Earlier in this chat:\n" + lines.reversed().joined(separator: "\n") + "\n\nNew message from the user:\n"
            + message
    }

    private func publish() {
        let current = snapshot
        for continuation in subscribers.values { continuation.yield(current) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
