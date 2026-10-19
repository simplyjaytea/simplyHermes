import Foundation
import Testing

@testable import HermesKit

/// Holds a reply back until the test lets it go.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// A scripted on-device model that records what it was asked.
private final class ScriptedExecutor: LocalModelExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()
    private let gate: Gate?

    private struct State {
        var availability: LocalModelAvailability = .available
        var fails = false
        var answer: @Sendable (String) -> String = { _ in "reply" }
        var prompts: [String] = []
        var instructions: [String] = []
    }

    init(gate: Gate? = nil) {
        self.gate = gate
    }

    var availability: LocalModelAvailability {
        get { lock.withLock { state.availability } }
        set { lock.withLock { state.availability = newValue } }
    }

    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }

    var answer: @Sendable (String) -> String {
        get { lock.withLock { state.answer } }
        set { lock.withLock { state.answer = newValue } }
    }

    var prompts: [String] { lock.withLock { state.prompts } }
    var instructions: [String] { lock.withLock { state.instructions } }

    func respond(instructions: String, prompt: String) async throws -> String {
        lock.withLock {
            state.prompts.append(prompt)
            state.instructions.append(instructions)
        }
        await gate?.wait()
        if fails { throw CancellationError() }
        return answer(prompt)
    }
}

struct OfflineChatControllerTests {
    private func makeController(
        _ executor: ScriptedExecutor, store: (any OfflineChatStore)? = nil, session: String = "s1"
    ) async throws -> (OfflineChatController, any OfflineChatStore) {
        let store = try store ?? HermesCache().offlineChats
        let controller = await OfflineChatController(
            store: store, executor: { executor }, connection: "x", sessionID: session,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        return (controller, store)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("The condition did not come true in time.")
    }

    // MARK: - Replies

    @Test func theReplyIsSavedBesideThePrompt() async throws {
        let executor = ScriptedExecutor()
        executor.answer = { "reply to: \($0)" }
        let (controller, store) = try await makeController(executor)
        await controller.send("  Hello there  ")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.role) == [.user, .assistant])
        #expect(snapshot.messages.map(\.text) == ["Hello there", "reply to: Hello there"])
        #expect(snapshot.chat?.title == "Hello there")
        #expect(snapshot.chat?.sessionID == "s1")
        #expect(!snapshot.isReplying)
        #expect(snapshot.failure == nil)
        // The first prompt travels alone; the model is told it has no tools.
        #expect(executor.prompts == ["Hello there"])
        #expect(executor.instructions.first?.contains("no tools") == true)
        // Both messages are in the store.
        let chatID = try #require(snapshot.chat?.id)
        #expect(try await store.messages(inChat: chatID, connection: "x") == snapshot.messages)
    }

    @Test func laterPromptsCarryTheChatSoFar() async throws {
        let executor = ScriptedExecutor()
        executor.answer = { _ in "fine" }
        let (controller, _) = try await makeController(executor)
        await controller.send("Hello")
        await controller.send("How are you?")
        #expect(
            executor.prompts.last == """
                Earlier in this chat:
                User: Hello
                Assistant: fine

                New message from the user:
                How are you?
                """)
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.text) == ["Hello", "fine", "How are you?", "fine"])
        #expect(snapshot.messages.map(\.id) == [1, 2, 3, 4])
    }

    @Test func blankTextIsIgnored() async throws {
        let executor = ScriptedExecutor()
        let (controller, store) = try await makeController(executor)
        await controller.send("   \n ")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.isEmpty)
        #expect(snapshot.chat == nil)
        #expect(executor.prompts.isEmpty)
        #expect(try await store.chats(connection: "x", limit: 10).isEmpty)
    }

    // MARK: - Failures

    @Test func anUnavailableModelKeepsThePromptAndSaysWhy() async throws {
        let executor = ScriptedExecutor()
        executor.availability = .unavailable(.disabled)
        let (controller, _) = try await makeController(executor)
        await controller.send("Are you there?")
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.role) == [.user])
        #expect(snapshot.failure == .unavailable(.disabled))
        #expect(executor.prompts.isEmpty)

        // Once the model is ready, the next message works and the failure goes away.
        executor.availability = .available
        await controller.send("Now?")
        let recovered = await controller.snapshot
        #expect(recovered.failure == nil)
        #expect(recovered.messages.map(\.role) == [.user, .user, .assistant])
    }

    @Test func aFailingModelIsReported() async throws {
        let executor = ScriptedExecutor()
        executor.fails = true
        let (controller, _) = try await makeController(executor)
        await controller.send("Hello")
        let snapshot = await controller.snapshot
        #expect(snapshot.failure == .modelFailed)
        #expect(snapshot.messages.map(\.role) == [.user])
        #expect(!snapshot.isReplying)
    }

    @Test func aBlankReplyIsAFailure() async throws {
        let executor = ScriptedExecutor()
        executor.answer = { _ in " \n " }
        let (controller, _) = try await makeController(executor)
        await controller.send("Hello")
        let snapshot = await controller.snapshot
        #expect(snapshot.failure == .modelFailed)
        #expect(snapshot.messages.count == 1)
    }

    // MARK: - Chat lifetime

    @Test func theChatSurvivesARelaunch() async throws {
        let executor = ScriptedExecutor()
        let (first, store) = try await makeController(executor)
        await first.send("Hello")
        let before = await first.snapshot

        let (second, _) = try await makeController(executor, store: store)
        let after = await second.snapshot
        #expect(after.chat == before.chat)
        #expect(after.messages == before.messages)
        // And it carries on in the same chat.
        await second.send("Again")
        let continued = await second.snapshot
        #expect(continued.messages.count == 4)
        #expect(continued.chat?.id == before.chat?.id)
    }

    @Test func eachServerChatHasItsOwnOfflineChat() async throws {
        let executor = ScriptedExecutor()
        let (first, store) = try await makeController(executor, session: "s1")
        let (second, _) = try await makeController(executor, store: store, session: "s2")
        await first.send("In the first chat")
        let other = await second.snapshot
        #expect(other.messages.isEmpty)
        #expect(other.chat == nil)
    }

    @Test func closingTheChatEmptiesItAndTheNextMessageStartsANewOne() async throws {
        let executor = ScriptedExecutor()
        let (controller, store) = try await makeController(executor)
        await controller.send("One")
        let firstID = try #require(await controller.snapshot.chat?.id)
        await controller.resolve(.dismissed)
        let closed = await controller.snapshot
        #expect(closed.chat == nil)
        #expect(closed.messages.isEmpty)
        #expect(try await store.currentChat(forSession: "s1", connection: "x") == nil)

        await controller.send("Two")
        let next = await controller.snapshot
        #expect(next.chat?.id != firstID)
        #expect(next.messages.map(\.text) == ["Two", "reply"])
        // No history leaks into the new chat.
        #expect(executor.prompts.last == "Two")
        // The closed chat keeps what it had.
        #expect(try await store.messages(inChat: firstID, connection: "x").map(\.text) == ["One", "reply"])
    }

    // MARK: - Order and timing

    @Test func promptsAreAnsweredOneAtATimeInTheOrderTheyCame() async throws {
        let gate = Gate()
        let executor = ScriptedExecutor(gate: gate)
        executor.answer = { prompt in "answer " + (prompt.hasSuffix("two") ? "two" : "one") }
        let (controller, _) = try await makeController(executor)

        let first = Task { await controller.send("one") }
        try await waitUntil { executor.prompts.count == 1 }
        let second = Task { await controller.send("two") }
        // The second prompt shows up at once, although the model is still busy with the first.
        try await waitUntil { await controller.snapshot.messages.count == 2 }
        #expect(await controller.snapshot.isReplying)
        #expect(executor.prompts.count == 1)

        await gate.open()
        await first.value
        await second.value
        let snapshot = await controller.snapshot
        #expect(snapshot.messages.map(\.text) == ["one", "two", "answer one", "answer two"])
        #expect(!snapshot.isReplying)
        #expect(executor.prompts.count == 2)
        // The second prompt sees the first answer but not itself, and no later prompt.
        #expect(executor.prompts.last?.contains("Assistant: answer one") == true)
        #expect(executor.prompts.last?.hasSuffix("New message from the user:\ntwo") == true)
    }

    @Test func aReplyThatArrivesAfterTheChatWasClosedIsDropped() async throws {
        let gate = Gate()
        let executor = ScriptedExecutor(gate: gate)
        let (controller, store) = try await makeController(executor)
        let sending = Task { await controller.send("slow question") }
        try await waitUntil { executor.prompts.count == 1 }
        let chatID = try #require(await controller.snapshot.chat?.id)

        await controller.resolve(.sent)
        await gate.open()
        await sending.value

        let snapshot = await controller.snapshot
        #expect(snapshot.messages.isEmpty)
        #expect(snapshot.chat == nil)
        #expect(!snapshot.isReplying)
        // The late reply was not written anywhere: the closed chat holds the prompt only.
        #expect(try await store.messages(inChat: chatID, connection: "x").map(\.text) == ["slow question"])
        #expect(try await store.currentChat(forSession: "s1", connection: "x") == nil)
    }

    @Test func statesYieldTheChatAsItChanges() async throws {
        let executor = ScriptedExecutor()
        let (controller, _) = try await makeController(executor)
        let states = await controller.states()
        var iterator = states.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial?.messages.isEmpty == true)

        await controller.send("Hello")
        // Only the newest snapshot is kept for a slow reader.
        let latest = await iterator.next()
        #expect(latest?.messages.map(\.role) == [.user, .assistant])
        #expect(latest?.isReplying == false)
    }

    // MARK: - History

    @Test func historyIsCutFromTheOldestEnd() {
        let when = Date(timeIntervalSince1970: 0)
        func turn(_ id: Int, _ role: OfflineChatMessage.Role, _ text: String) -> OfflineChatMessage {
            OfflineChatMessage(chatID: "c", id: id, role: role, text: text, createdAt: when)
        }
        let history = [
            turn(1, .user, "oldest question"), turn(2, .assistant, "oldest answer"), turn(3, .user, "newer question"),
            turn(4, .assistant, "newer answer"),
        ]
        // "User: newer question" is 20 characters and "Assistant: newer answer" 23; 43 fit, the older lines do not.
        let prompt = OfflineChatController.prompt(history: history, message: "next", limit: 45)
        let expected = [
            "Earlier in this chat:", "User: newer question", "Assistant: newer answer", "",
            "New message from the user:", "next",
        ].joined(separator: "\n")
        #expect(prompt == expected)
        #expect(OfflineChatController.prompt(history: history, message: "next", limit: 0) == "next")
        #expect(OfflineChatController.prompt(history: [], message: "next") == "next")
    }
}
