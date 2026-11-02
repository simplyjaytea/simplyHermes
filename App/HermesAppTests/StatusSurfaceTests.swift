import HermesKit
import Testing

@testable import HermesUI

/// WP-8: the status surfaces read one source. A chat with no server says so, shows no outage banner and never
/// shows the hard-coded "Connected" the header used to show.
@MainActor
struct StatusSurfaceTests {
    private func chat(_ cache: HermesCache) -> LiveChatModel {
        let services = ConnectionServices(credentials: InMemoryCredentialStore(), unlocker: AlwaysUnlocked())
        let connections = ConnectionsModel(store: nil, services: services)
        return LiveChatModel(
            connections: connections, broker: ServerRequestBroker(), storedSessionID: "s1", outbox: cache.outbox)
    }

    @Test func aChatWithNoServerIsSetUpAndShowsNoBanner() throws {
        let model = chat(try HermesCache())

        #expect(model.status.pill == .noServer)
        #expect(OutageBanner.shows(model.status) == false)
        #expect(model.strip.connection == .offline)
    }

    @Test func thePillAndTheStripUseTheSameStatus() throws {
        let model = chat(try HermesCache())

        #expect(StripConnection(pill: model.status.pill) == model.strip.connection)
        #expect(model.serverName == "the server")
    }

    @Test func theDefaultChatModeIsOnlineAndSavingItSticks() {
        let saved = ChatModeDefault.current
        defer { ChatModeDefault.save(saved, to: .standard) }

        ChatModeDefault.save(.local, to: .standard)
        #expect(ChatModeDefault.current == .local)
        ChatModeDefault.save(.online, to: .standard)
        #expect(ChatModeDefault.current == .online)
    }
}
