import Testing

@testable import HermesUI

/// Offline when the server cannot be reached.
private struct Offline: Error {}

private func serverChat(_ id: String) -> SessionListItem {
    SessionListItem(id: id, title: "New chat", time: "Now", isPinned: false, serverName: "home-server")
}

/// Counts the server chats a New chat creates, and records the first messages handed to them.
@MainActor
private final class Recorder {
    struct HandOff: Equatable {
        let sessionID: String
        let text: String
    }

    private(set) var creates = 0
    private(set) var handedOff: [HandOff] = []

    func created() -> String {
        creates += 1
        return "stored-\(creates)"
    }

    func handOff(_ sessionID: String, _ text: String) {
        handedOff.append(HandOff(sessionID: sessionID, text: text))
    }
}

/// Holds a create open until the test lets it go, and counts how many creates began.
@MainActor
private final class CreateGate {
    private(set) var started = 0
    private var isOpen = false
    private var waiting: CheckedContinuation<Void, Never>?

    func begin() async {
        started += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }
}

@MainActor
struct NewChatTests {
    /// A shell whose server creates chats named stored-1, stored-2, and so on, and records the first messages it gets.
    private func serverShell() -> (model: ShellModel, recorder: Recorder) {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        let recorder = Recorder()
        model.startServerChat = { serverChat(recorder.created()) }
        model.handOffFirstMessage = { id, text, _ in recorder.handOff(id, text) }
        return (model, recorder)
    }

    /// Opens a New chat and types `text` into it. Returns the chat's id.
    private func typeInNewChat(_ text: String, in model: ShellModel) throws -> String {
        model.newChat()
        let id = try #require(model.selectedSessionID)
        model.drafts[id] = text
        return id
    }

    @Test func newChatWithoutServerMakesPlaceholder() {
        let model = ShellModel(sessions: [], selectedSessionID: nil)

        model.newChat()

        #expect(model.selectedSessionID?.hasPrefix("new-") == true)
        #expect(model.serverSessionIDs.isEmpty)
    }

    @Test func newChatWithServerCreatesNothingUntilTheFirstMessage() {
        let (model, recorder) = serverShell()

        model.newChat()

        #expect(model.selectedSessionID?.hasPrefix("new-") == true)
        #expect(model.serverSessionIDs.isEmpty)
        #expect(recorder.creates == 0)
    }

    @Test func firstMessageCreatesTheServerChatAndSendsIt() async throws {
        let (model, recorder) = serverShell()
        let id = try typeInNewChat("hello", in: model)

        _ = await model.send(in: id)?.value

        #expect(recorder.creates == 1)
        #expect(recorder.handedOff == [Recorder.HandOff(sessionID: "stored-1", text: "hello")])
        #expect(model.selectedSessionID == "stored-1")
        #expect(model.serverSessionIDs.contains("stored-1"))
        #expect(!model.sessions.contains { $0.id.hasPrefix("new-") })
        #expect(model.drafts["stored-1"] == nil)
        #expect(model.newChatError == nil)
    }

    @Test func emptyFirstMessageCreatesNothing() throws {
        let (model, recorder) = serverShell()
        let id = try typeInNewChat("   ", in: model)

        let task = model.send(in: id)

        #expect(task == nil)
        #expect(recorder.creates == 0)
        #expect(model.newChatError == nil)
    }

    @Test func failedFirstMessageKeepsTheTextAndSendsNothing() async throws {
        let (model, recorder) = serverShell()
        model.startServerChat = { throw Offline() }
        let id = try typeInNewChat("hello", in: model)

        _ = await model.send(in: id)?.value

        #expect(model.selectedSessionID == id)
        #expect(model.drafts[id] == "hello")
        #expect(recorder.handedOff.isEmpty)
        #expect(model.newChatError == "Could not start a new chat. Try again.")
    }

    @Test func failedFirstMessageKeepsTheOtherOpenChatsAndTheirDrafts() async throws {
        let model = ShellModel(selectedSessionID: "blog")
        model.drafts["blog"] = "half a thought"
        model.startServerChat = { throw Offline() }
        let id = try typeInNewChat("hello", in: model)

        _ = await model.send(in: id)?.value

        #expect(model.openSessionIDs == ["blog", id])
        #expect(model.drafts["blog"] == "half a thought")
        #expect(model.drafts[id] == "hello")
    }

    @Test func theMessageNamesAServerThatIsNotConnected() async throws {
        let (model, _) = serverShell()
        let id = try typeInNewChat("hello", in: model)

        model.startServerChat = { throw ServerNotConnectedError(serverName: "Home", isConnecting: false) }
        _ = await model.send(in: id)?.value
        #expect(model.newChatError == "Home is not connected. Connect to it, then try again.")

        model.startServerChat = { throw ServerNotConnectedError(serverName: "Home", isConnecting: true) }
        _ = await model.send(in: id)?.value
        #expect(model.newChatError == "Home is still connecting. Try again in a moment.")
    }

    @Test func aFailedFirstMessageCanBeSentAgain() async throws {
        let (model, recorder) = serverShell()
        model.startServerChat = { throw Offline() }
        let id = try typeInNewChat("hello", in: model)
        _ = await model.send(in: id)?.value
        #expect(model.newChatError != nil)

        model.startServerChat = { serverChat(recorder.created()) }
        _ = await model.send(in: id)?.value

        #expect(model.newChatError == nil)
        #expect(model.selectedSessionID == "stored-1")
        #expect(recorder.handedOff == [Recorder.HandOff(sessionID: "stored-1", text: "hello")])
    }

    @Test func repeatSendWhileTheChatIsStartingSendsOnce() async throws {
        let (model, recorder) = serverShell()
        let gate = CreateGate()
        model.startServerChat = {
            await gate.begin()
            return serverChat(recorder.created())
        }
        let id = try typeInNewChat("hello", in: model)

        let first = model.send(in: id)
        let second = model.send(in: id)
        gate.open()
        _ = await first?.value
        _ = await second?.value

        #expect(gate.started == 1)
        #expect(recorder.handedOff.count == 1)
        #expect(model.sessions.filter { $0.id == "stored-1" }.count == 1)
    }

    @Test func repeatNewChatShowsTheEmptyChatAlreadyOpen() {
        let (model, recorder) = serverShell()

        model.newChat()
        let first = model.selectedSessionID
        model.newChat()

        #expect(model.selectedSessionID == first)
        #expect(model.sessions.filter { $0.id.hasPrefix("new-") }.count == 1)
        #expect(recorder.creates == 0)
    }

    @Test func firstMessageWithoutAnActiveServerKeepsTheText() async throws {
        let (model, recorder) = serverShell()
        model.startServerChat = { nil }
        let id = try typeInNewChat("hello", in: model)

        _ = await model.send(in: id)?.value

        #expect(model.selectedSessionID == id)
        #expect(model.drafts[id] == "hello")
        #expect(recorder.handedOff.isEmpty)
        #expect(model.newChatError == "Could not start a new chat. Try again.")
    }

    @Test func listSyncKeepsAStartedChatTheListDoesNotShowYet() async throws {
        let (model, _) = serverShell()
        let id = try typeInNewChat("hello", in: model)
        _ = await model.send(in: id)?.value

        model.syncSessions([])

        #expect(model.openSessionIDs == ["stored-1"])
        #expect(model.serverSessionIDs.contains("stored-1"))
    }

    @Test func listSyncReplacesTheStartedChatOnceListed() async throws {
        let (model, _) = serverShell()
        let id = try typeInNewChat("hello", in: model)
        _ = await model.send(in: id)?.value

        model.syncSessions([serverChat("stored-1")])

        #expect(model.sessions.filter { $0.id == "stored-1" }.count == 1)
        #expect(model.openSessionIDs == ["stored-1"])
    }
}
