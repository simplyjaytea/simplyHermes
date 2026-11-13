import HermesKit
import Testing

@testable import HermesUI

/// WP-8: the status surfaces read one source. A chat with no server says so, shows no outage banner and never
/// shows the hard-coded "Connected" the header used to show.
/// The phase a test sets for a chat's status to read.
@MainActor
final class PhaseBox {
    var value: ConnectionPhase?
}

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

    /// Drives the connection phase through the test seam, so each phase's pill is checked through the chat's own status.
    @Test func thePillFollowsTheConnectionPhase() throws {
        let phase = PhaseBox()
        let connections = ConnectionsModel.preview()
        let server = try #require(ConnectionsModel.sampleConnections.first)
        connections.setActive(server.id)
        let model = LiveChatModel(
            connections: connections, broker: ServerRequestBroker(), storedSessionID: "s1",
            outbox: try HermesCache().outbox, phaseSource: { phase.value })

        phase.value = .connecting
        #expect(model.status.pill == .connecting)

        phase.value = .reconnecting(attempt: 2)
        #expect(model.status.pill == .reconnecting)

        phase.value = .failed(.unreachable("the test has no network"))
        #expect(model.status.pill == .unreachable)
        #expect(OutageBanner.shows(model.status))
        #expect(model.strip.connection == .offline)

        phase.value = .signInRequired
        #expect(model.status.pill == .needsAttention(.signIn))
        #expect(OutageBanner.shows(model.status) == false)
    }

    /// Row 108: a chat the store dropped on a server switch must not attach itself to the new server when its pill moves
    /// into `.connected`. The test drives the pill by hand, because the phase seam does not fire the observation.
    @Test func aRetiredChatDoesNotAttachWhenItsPillComesBack() throws {
        let connections = ConnectionsModel.preview()
        let server = try #require(ConnectionsModel.sampleConnections.first)
        connections.setActive(server.id)
        let phase = PhaseBox()
        func makeChat() throws -> LiveChatModel {
            LiveChatModel(
                connections: connections, broker: ServerRequestBroker(), storedSessionID: "s1",
                outbox: try HermesCache().outbox, phaseSource: { phase.value })
        }
        func comeBack(_ chat: LiveChatModel) async {
            phase.value = .failed(.unreachable("the test has no network"))
            chat.pillChanged()
            phase.value = .connected(ServerSummary())
            chat.pillChanged()
            // The attach runs in a task the call starts.
            for _ in 0..<20 { await Task.yield() }
        }

        // Control: a live chat attaches when it comes back, which moves its phase off `.loading` (the preview has no
        // connection manager, so the attempt fails). That shows the check below can see an attach.
        let live = try makeChat()
        await comeBack(live)
        #expect(live.phase != .loading)

        let retired = try makeChat()
        retired.retire()
        await comeBack(retired)
        #expect(retired.phase == .loading)
        #expect(retired.isRetired)
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
