import Testing

@testable import HermesUI

/// Offline when the server cannot be reached.
private struct Offline: Error {}

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
    private func serverChat(_ id: String) -> SessionListItem {
        SessionListItem(id: id, title: "New chat", time: "Now", isPinned: false, serverName: "home-server")
    }

    @Test func newChatWithoutServerMakesPlaceholder() {
        let model = ShellModel(sessions: [], selectedSessionID: nil)

        let task = model.newChat()

        #expect(task == nil)
        #expect(model.selectedSessionID?.hasPrefix("new-") == true)
        #expect(model.serverSessionIDs.isEmpty)
    }

    @Test func newChatWithServerOpensTheServerChat() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { serverChat("stored-1") }

        _ = await model.newChat()?.value

        #expect(model.selectedSessionID == "stored-1")
        #expect(model.serverSessionIDs.contains("stored-1"))
        #expect(!model.sessions.contains { $0.id.hasPrefix("new-") })
    }

    @Test func failedServerChatOpensNothing() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { throw Offline() }

        _ = await model.newChat()?.value

        #expect(model.sessions.isEmpty)
        #expect(model.selectedSessionID == nil)
    }

    @Test func failedServerChatKeepsTheOpenChatAndItsDraft() async {
        let model = ShellModel(selectedSessionID: "blog")
        model.drafts["blog"] = "half a thought"
        model.startServerChat = { throw Offline() }

        _ = await model.newChat()?.value

        #expect(model.selectedSessionID == "blog")
        #expect(model.openSessionIDs == ["blog"])
        #expect(model.drafts["blog"] == "half a thought")
        #expect(model.newChatError == "Could not start a new chat. Try again.")
    }

    @Test func theMessageNamesAServerThatIsNotConnected() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { throw ServerNotConnectedError(serverName: "Home", isConnecting: false) }
        _ = await model.newChat()?.value
        #expect(model.newChatError == "Home is not connected. Connect to it, then try again.")

        model.startServerChat = { throw ServerNotConnectedError(serverName: "Home", isConnecting: true) }
        _ = await model.newChat()?.value
        #expect(model.newChatError == "Home is still connecting. Try again in a moment.")
    }

    @Test func newChatAfterAFailureTriesAgainAndClearsTheMessage() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { throw Offline() }
        _ = await model.newChat()?.value
        #expect(model.newChatError != nil)

        model.startServerChat = { serverChat("stored-1") }
        _ = await model.newChat()?.value

        #expect(model.newChatError == nil)
        #expect(model.selectedSessionID == "stored-1")
    }

    @Test func repeatNewChatWhileOneIsStartingMakesOneChat() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        let gate = CreateGate()
        model.startServerChat = {
            await gate.begin()
            return serverChat("stored-1")
        }

        let first = model.newChat()
        let second = model.newChat()
        await Task.yield()
        let third = model.newChat()
        gate.open()
        _ = await first?.value
        _ = await second?.value
        _ = await third?.value

        #expect(gate.started == 1)
        #expect(model.sessions.filter { $0.id == "stored-1" }.count == 1)
        #expect(model.openSessionIDs == ["stored-1"])
    }

    @Test func noActiveServerMakesAPlaceholder() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { nil }

        _ = await model.newChat()?.value

        #expect(model.selectedSessionID?.hasPrefix("new-") == true)
        #expect(model.serverSessionIDs.isEmpty)
        #expect(model.newChatError == nil)
    }

    @Test func listSyncKeepsAServerChatTheListDoesNotShowYet() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { serverChat("stored-1") }
        _ = await model.newChat()?.value

        model.syncSessions([])

        #expect(model.openSessionIDs == ["stored-1"])
        #expect(model.serverSessionIDs.contains("stored-1"))
    }

    @Test func listSyncReplacesTheStartedChatOnceListed() async {
        let model = ShellModel(sessions: [], selectedSessionID: nil)
        model.startServerChat = { serverChat("stored-1") }
        _ = await model.newChat()?.value

        model.syncSessions([serverChat("stored-1")])

        #expect(model.sessions.filter { $0.id == "stored-1" }.count == 1)
        #expect(model.openSessionIDs == ["stored-1"])
    }
}
