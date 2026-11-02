import Foundation

/// Why the last reply in a local chat did not arrive.
public enum LocalChatFailure: Sendable, Equatable {
    /// The on-device model cannot answer, for this reason.
    case unavailable(LocalModelUnavailable)
    /// The model failed, or answered with nothing.
    case modelFailed
    /// The message could not be saved.
    case notSaved
}

/// What one local chat holds now.
public struct LocalChatSnapshot: Sendable, Equatable {
    /// The chat. Nil for a new chat until its first message is sent.
    public var chat: LocalChat?
    /// Its messages, oldest first.
    public var messages: [LocalChatMessage]
    /// True while the on-device model works on a reply.
    public var isReplying: Bool
    /// Why the last reply failed, if it did.
    public var failure: LocalChatFailure?

    /// True when the newest message is the user's and has no reply, and none is being written. That is the state a
    /// reply that threw, came back blank, or was cut off by a relaunch leaves behind. Retry asks again.
    public var needsReply: Bool {
        !isReplying && messages.last?.author == .user
    }

    /// Creates a snapshot. The default is an empty new chat.
    public init(
        chat: LocalChat? = nil, messages: [LocalChatMessage] = [], isReplying: Bool = false,
        failure: LocalChatFailure? = nil
    ) {
        self.chat = chat
        self.messages = messages
        self.isReplying = isReplying
        self.failure = failure
    }
}

/// A chat that lives on this iPhone (WP-7). It saves what the user writes, asks an on-device model for the reply, and
/// saves the reply with the name of the model that wrote it.
///
/// The controller has no transport, gateway or connection parameter: it can only reach the store and the answerer.
/// A reply is saved only when the model returns text that is not blank. A failure leaves the user's message saved and
/// adds no assistant row.
///
/// Messages are answered one at a time, in the order they were written.
public actor LocalChatController {
    /// Characters of earlier chat sent along with a new message. The on-device model has a small context window.
    public static let historyLimit = 6000

    /// What the model is told about its situation.
    public static let instructions = """
        You are the assistant inside simplyHermes on the user's iPhone. Answer from what you know, in a few short \
        sentences. You have no tools, no files, no terminal and no internet.
        """

    /// The chat's id. Fixed when the chat is created in the UI, so the sidebar can name it before the first message.
    public let chatID: UUID
    private let store: any LocalChatStore
    private let answerer: @Sendable () -> any LocalChatAnswerer
    private let now: @Sendable () -> Date

    private var chat: LocalChat?
    private var messages: [LocalChatMessage] = []
    private var unanswered: [LocalChatMessage] = []
    private var isReplying = false
    private var failure: LocalChatFailure?
    private var subscribers: [UUID: AsyncStream<LocalChatSnapshot>.Continuation] = [:]
    private var replyTask: Task<Void, Never>?
    private var opening: Task<LocalChat, Error>?

    /// The id the chat has, or will have once its first message is sent. A chat that exists in the store opens with
    /// its saved messages. `answerer` is asked for the model on every reply, so a model chosen in Settings applies at
    /// once.
    public init(
        store: any LocalChatStore, answerer: @escaping @Sendable () -> any LocalChatAnswerer, chatID: UUID,
        now: @escaping @Sendable () -> Date = { Date() }
    ) async {
        self.store = store
        self.answerer = answerer
        self.chatID = chatID
        self.now = now
        if let open = try? await store.chat(chatID) {
            chat = open
            messages = (try? await store.messages(inChat: chatID)) ?? []
        }
    }

    /// The chat as it is now.
    public var snapshot: LocalChatSnapshot {
        LocalChatSnapshot(chat: chat, messages: messages, isReplying: isReplying, failure: failure)
    }

    /// A stream of the chat, starting with the current value and yielding after every change.
    public func states() -> AsyncStream<LocalChatSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LocalChatSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        return stream
    }

    /// Saves `text` as the user's message and waits until the on-device model has answered it and any earlier
    /// message. Returns true once the message is saved. Blank text is ignored and returns false.
    @discardableResult
    public func send(_ text: String) async -> Bool {
        let saved = await submit(text)
        await replyTask?.value
        return saved
    }

    /// Saves `text` as the user's message and starts the reply in the background, so the caller need not wait for
    /// the model. Returns true once the message is saved. Blank text is ignored and returns false.
    @discardableResult
    public func submit(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        failure = nil
        let prompt: LocalChatMessage
        do {
            let current = try await openChat(startingWith: trimmed)
            prompt = try await store.appendUserMessage(trimmed, toChat: current.id, at: now())
        } catch {
            failure = .notSaved
            publish()
            return false
        }
        messages.append(prompt)
        unanswered.append(prompt)
        publish()
        guard !isReplying else { return true }
        isReplying = true
        publish()
        replyTask = Task { await self.drainReplies() }
        return true
    }

    /// Asks the model again for the newest message when it has no reply (see ``LocalChatSnapshot/needsReply``). It adds
    /// one reply at most and writes no user row again. It returns when the attempt has finished.
    public func retry() async {
        guard !isReplying, let last = messages.last, last.author == .user else { return }
        failure = nil
        isReplying = true
        unanswered.append(last)
        publish()
        replyTask = Task { await self.drainReplies() }
        await replyTask?.value
    }

    /// Answers the waiting messages one at a time. A message saved while this runs is picked up by the same loop.
    private func drainReplies() async {
        while !unanswered.isEmpty {
            await answer(unanswered.removeFirst())
        }
        isReplying = false
        publish()
    }

    // MARK: - Replies

    /// Creates the chat on its first message. A message that arrives while the chat is being created waits for the
    /// same creation, so the chat is inserted once.
    private func openChat(startingWith text: String) async throws -> LocalChat {
        if let chat { return chat }
        if let opening { return try await opening.value }
        let store = self.store
        let id = chatID
        let title = LocalChat.title(forPrompt: text)
        let date = now()
        let creation = Task { try await store.createChat(id: id, title: title, at: date) }
        opening = creation
        defer { opening = nil }
        let started = try await creation.value
        chat = started
        return started
    }

    private func answer(_ prompt: LocalChatMessage) async {
        let model = answerer()
        if case .unavailable(let reason) = model.availability {
            failure = .unavailable(reason)
            publish()
            return
        }
        // The chat so far, without this message and without messages that still wait for their turn.
        let waiting = Set(unanswered.map(\.id))
        let history = messages.filter { $0.id != prompt.id && !waiting.contains($0.id) }
        // WP-9 replaces `try?` with a typed failure that keeps the model's error.
        let reply = try? await model.answer(
            instructions: Self.instructions, prompt: Self.prompt(history: history, message: prompt.text))
        let text = reply?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let reply, !text.isEmpty else {
            failure = .modelFailed
            publish()
            return
        }
        do {
            let saved = try await store.appendReply(
                LocalReply(text: text, answeredBy: reply.answeredBy), toChat: prompt.chatID, at: now())
            messages.append(saved)
            failure = nil
        } catch {
            failure = .notSaved
        }
        publish()
    }

    /// The text sent to the model: as much of the chat so far as fits in ``historyLimit`` (the newest turns win),
    /// then the new message.
    static func prompt(history: [LocalChatMessage], message: String, limit: Int = historyLimit) -> String {
        var lines: [String] = []
        var used = 0
        for entry in history.reversed() {
            let speaker: String
            switch entry.author {
            case .user: speaker = "User"
            case .assistant: speaker = "Assistant"
            }
            let line = "\(speaker): \(entry.text)"
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
