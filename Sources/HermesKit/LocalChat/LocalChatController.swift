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
    /// The user messages that have no reply, and are not waiting for one: a question whose reply threw, came back
    /// blank, or was cut off by a relaunch. Each can be retried. Computed from the stored messages, so it survives a
    /// reopen.
    public var unansweredIDs: [Int]

    /// True when some user message has no reply. Retry asks again for each one.
    public var needsReply: Bool { !unansweredIDs.isEmpty }

    /// Creates a snapshot. The default is an empty new chat.
    public init(
        chat: LocalChat? = nil, messages: [LocalChatMessage] = [], isReplying: Bool = false,
        failure: LocalChatFailure? = nil, unansweredIDs: [Int] = []
    ) {
        self.chat = chat
        self.messages = messages
        self.isReplying = isReplying
        self.failure = failure
        self.unansweredIDs = unansweredIDs
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
    /// Read before every reply, so a memory saved or deleted in Settings applies to the next answer.
    private let memory: @Sendable () async -> [LocalMemory]
    private let now: @Sendable () -> Date

    private var chat: LocalChat?
    private var messages: [LocalChatMessage] = []
    private var unanswered: [LocalChatMessage] = []
    /// The question whose reply is being written now. It is neither waiting nor unanswered until its reply is saved.
    private var answering: Int?
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
        memory: @escaping @Sendable () async -> [LocalMemory] = { [] },
        now: @escaping @Sendable () -> Date = { Date() }
    ) async {
        self.store = store
        self.answerer = answerer
        self.memory = memory
        self.chatID = chatID
        self.now = now
        if let open = try? await store.chat(chatID) {
            chat = open
            messages = (try? await store.messages(inChat: chatID)) ?? []
        }
    }

    /// The chat as it is now.
    public var snapshot: LocalChatSnapshot {
        LocalChatSnapshot(
            chat: chat, messages: messages, isReplying: isReplying, failure: failure,
            unansweredIDs: unansweredQuestionIDs())
    }

    /// The user messages with no reply that are not waiting for one (queued, or being answered now). A reply names the
    /// question it answers, so this is read from the stored rows.
    private func unansweredQuestionIDs() -> [Int] {
        let answered = Set(
            messages.compactMap { message -> Int? in
                if case .assistant(_, let question) = message.author { return question }
                return nil
            })
        let waiting = Set(unanswered.map(\.id)).union(answering.map { [$0] } ?? [])
        return messages.compactMap { message in
            message.author == .user && !answered.contains(message.id) && !waiting.contains(message.id)
                ? message.id : nil
        }
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

    /// Asks the model again for one unanswered question (see ``LocalChatSnapshot/unansweredIDs``). It adds one reply at
    /// most, answering that question, and writes no user row. Ids that are not unanswered questions are ignored. When no
    /// reply is being written, it returns once the attempt has finished. When one is, it queues this question and returns
    /// at once; the running reply loop writes the queued reply later.
    public func retry(messageID: Int) async {
        guard let question = messages.first(where: { $0.id == messageID }), question.author == .user,
            unansweredQuestionIDs().contains(messageID)
        else { return }
        failure = nil
        unanswered.append(question)
        guard !isReplying else {
            publish()
            return
        }
        isReplying = true
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

    private enum Attempt {
        case answered(LocalAnswer)
        case failed(LocalChatFailure)
    }

    /// Writes the reply to one question. The question stays out of the unanswered list until its reply is saved, so the
    /// screen never shows Retry for a question that is being answered.
    private func answer(_ prompt: LocalChatMessage) async {
        answering = prompt.id
        switch await attempt(prompt) {
        case .failed(let reason):
            failure = reason
        case .answered(let answer):
            do {
                let reply = LocalReply(text: answer.text, answeredBy: answer.answeredBy, inReplyTo: prompt.id)
                let saved = try await store.appendReply(reply, toChat: prompt.chatID, at: now())
                messages.append(saved)
                failure = nil
            } catch {
                failure = .notSaved
            }
        }
        answering = nil
        publish()
    }

    private func attempt(_ prompt: LocalChatMessage) async -> Attempt {
        let model = answerer()
        if case .unavailable(let reason) = model.availability { return .failed(.unavailable(reason)) }
        // The chat before this question. Later messages, which wait for their own turn, are not part of it.
        let history = messages.filter { $0.id < prompt.id }
        // WP-9 replaces `try?` with a typed failure that keeps the model's error.
        let answer = try? await model.answer(
            instructions: Self.instructions(memory: await memory()),
            prompt: Self.prompt(history: history, message: prompt.text))
        let text = answer?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let answer, !text.isEmpty else { return .failed(.modelFailed) }
        return .answered(LocalAnswer(text: text, answeredBy: answer.answeredBy))
    }

    /// ``instructions`` plus the user's saved memory, within ``LocalMemoryRules/promptBudget``.
    static func instructions(memory: [LocalMemory]) -> String {
        let block = LocalMemoryRules.instructionsBlock(memory)
        return block.isEmpty ? instructions : instructions + "\n\n" + block
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
