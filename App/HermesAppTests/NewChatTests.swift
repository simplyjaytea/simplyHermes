import Testing

@testable import HermesUI

/// Offline when the server cannot be reached.
private struct Offline: Error {}

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
