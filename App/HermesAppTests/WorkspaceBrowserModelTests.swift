import HermesUI
import Testing

@MainActor
struct WorkspaceBrowserModelTests {
    /// The Files tab keys its load on this, so it reloads when the user switches servers.
    @Test func loadKeyFollowsTheActiveServer() throws {
        let connections = ConnectionsModel.preview()
        let browser = WorkspaceBrowserModel(connections: connections)
        let first = browser.loadKey

        let other = try #require(connections.connections.first { $0.id != connections.active?.id })
        connections.setActive(other.id)

        #expect(browser.loadKey != first)
    }

    @Test func loadKeyIsNoneWithoutServers() {
        #expect(WorkspaceBrowserModel(connections: .preview([])).loadKey == "none")
    }
}
