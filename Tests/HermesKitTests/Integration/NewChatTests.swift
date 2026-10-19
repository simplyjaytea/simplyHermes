import Foundation
import HermesKit
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct NewChatPolicyTests {
    @Test func aSavedServerGetsARealChat() {
        #expect(NewChatPolicy.kind(hasServer: true) == .server)
        #expect(NewChatPolicy.kind(hasServer: false) == .placeholder)
    }

    @Test func newChatFollowsTheServerAndTheFirstMessage() {
        #expect(NewChatPolicy.plan(hasServer: true, hasText: false) == .serverChat, "opens the real chat")
        #expect(NewChatPolicy.plan(hasServer: true, hasText: true) == .serverChat, "the message goes to that chat")
        #expect(NewChatPolicy.plan(hasServer: false, hasText: false) == .placeholderChat, "today's behaviour")
        #expect(NewChatPolicy.plan(hasServer: false, hasText: true) == .needsServer, "today's behaviour")
    }

    @Test func aFailedStartIsSaidInCalmWords() {
        let dialog = IntentOutcome.couldNotStartChat.dialog
        #expect(dialog == "I could not start a new chat. Open simplyHermes to check the server, then try again.")
        #expect(dialog != IntentOutcome.notConnected.dialog, "a saved server that says no is not an unsaved server")
    }

    @Test func aMessageNamesNoBotUnlessTheIntentDoes() {
        let plain = IntentMapping.message(for: .newChat(text: "first"), id: "m1", now: now)
        #expect(plain?.profile == nil)
        let bot = IntentMapping.message(for: .askBot(bot: "ops", text: "status?"), id: "m2", now: now)
        #expect(bot?.profile == nil, "the app fills in the resolved bot name after it has found the bot")
        var named = OutboundMessage(id: "m3", text: "hi", target: .newChat, createdAt: now)
        named.profile = "ops"
        #expect(named != OutboundMessage(id: "m3", text: "hi", target: .newChat, createdAt: now))
    }
}

/// A gateway that answers `session.create` from a script.
private final class FakeCreator: SessionCreating, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [SessionCreateParams] = []
    private let outcome: Result<SessionCreateResult, any Error>

    init(_ outcome: Result<SessionCreateResult, any Error>) {
        self.outcome = outcome
    }

    var requests: [SessionCreateParams] { lock.withLock { calls } }

    func createSession(_ params: SessionCreateParams) async throws -> SessionCreateResult {
        lock.withLock { calls.append(params) }
        return try outcome.get()
    }
}

private func result(_ json: String) throws -> SessionCreateResult {
    try JSONDecoder().decode(SessionCreateResult.self, from: Data(json.utf8))
}

/// A `session.create` result. Leave `stored` or `key` nil to drop that field.
private func attachJSON(
    live: String = "9f365736", stored: String? = "20261014_030939_cf35cb", key: String? = nil
) -> String {
    var fields = [#""session_id":"\#(live)""#]
    if let stored { fields.append(#""stored_session_id":"\#(stored)""#) }
    if let key { fields.append(#""session_key":"\#(key)""#) }
    fields.append(
        """
        "message_count":0,"messages":[],"info":{"model":"fake-model","tools":{},"skills":{},"cwd":"/","branch":"b",\
        "project":null,"lazy":true,"desktop_contract":8,"profile_name":"default"}
        """)
    return "{" + fields.joined(separator: ",") + "}"
}

@Suite struct NewServerChatTests {
    @Test func askingForAChatUsesSessionCreateUnderTheChosenProfile() async throws {
        let gateway = FakeCreator(.success(try result(attachJSON())))
        let chat = try await NewServerChat.start(using: gateway, profile: "ops")
        #expect(gateway.requests == [SessionCreateParams(profile: "ops")])
        #expect(chat == StartedChat(storedSessionID: "20261014_030939_cf35cb", liveSessionID: "9f365736"))
    }

    @Test func noProfileLeavesItToTheConnection() async throws {
        let gateway = FakeCreator(.success(try result(attachJSON())))
        _ = try await NewServerChat.start(using: gateway, profile: nil)
        #expect(gateway.requests.first?.profile == nil)
        #expect(gateway.requests.first == SessionCreateParams())
    }

    @Test func theSessionKeyStandsInForAMissingStoredID() async throws {
        let gateway = FakeCreator(.success(try result(attachJSON(stored: nil, key: "20261014_030939_cf35cb"))))
        let chat = try await NewServerChat.start(using: gateway, profile: nil)
        #expect(chat.storedSessionID == "20261014_030939_cf35cb")
        #expect(chat.liveSessionID == "9f365736")
    }

    @Test func aChatWithNoStoredIDIsRefused() async throws {
        let gateway = FakeCreator(.success(try result(attachJSON(stored: nil))))
        await #expect(throws: NewChatFailure.refused(reason: "The server did not name the new chat.")) {
            _ = try await NewServerChat.start(using: gateway, profile: nil)
        }
    }

    @Test func aServerThatSaysNoIsRefusedWithItsReason() async {
        let gateway = FakeCreator(.failure(RPCError(code: 4000, message: "unknown profile")))
        await #expect(throws: NewChatFailure.refused(reason: "unknown profile")) {
            _ = try await NewServerChat.start(using: gateway, profile: "ghost")
        }
    }

    @Test func anyOtherFailureMeansTheServerIsNotReachable() async {
        for error in [GatewayClientError.notConnected, .disconnected, .timedOut(method: "session.create"), .stopped] {
            let gateway = FakeCreator(.failure(error))
            await #expect(throws: NewChatFailure.notReachable, "\(error)") {
                _ = try await NewServerChat.start(using: gateway, profile: nil)
            }
        }
    }
}

/// The real gateway client against a fake socket: what `session.create` looks like on the wire.
@Suite(.serialized) struct NewChatOverTheGatewayTests {
    private func connectedClient() async throws -> (client: GatewayClient, socket: FakeSocket) {
        let transport = FakeTransport()
        var config = GatewayClientConfig()
        config.reconnect = ReconnectPolicy(jitter: { $0 })
        let client = GatewayClient(
            endpoint: HermesEndpoint(string: "https://hermes.example")!, transport: transport,
            credentials: { _ in .ticket("t1") }, clock: ManualClock(), config: config)
        let log = EventLog(await client.events())
        let socket = FakeSocket()
        socket.serve { frame in
            guard let id = frame.id, frame.method == "session.create" else { return [] }
            return [Frames.result(id: id, attachJSON())]
        }
        transport.enqueue(.socket(socket))
        await client.start()
        try await waitUntil("connected") { log.states.contains(.connected) }
        return (client, socket)
    }

    @Test func theChosenProfileTravelsInTheCall() async throws {
        let (client, socket) = try await connectedClient()
        let chat = try await NewServerChat.start(using: client, profile: "ops")
        #expect(socket.requests("session.create").count == 1)
        #expect(socket.requests("session.create").first?.params?["profile"] as? String == "ops")
        #expect(chat.storedSessionID == "20261014_030939_cf35cb")
        await client.stop()
    }

    @Test func aProfileSetForTheCallBeatsTheConnectionsActiveProfile() async throws {
        let (client, socket) = try await connectedClient()
        await client.setProfile("default")
        _ = try await NewServerChat.start(using: client, profile: "ops")
        #expect(socket.requests("session.create").last?.params?["profile"] as? String == "ops")
        await client.stop()
    }

    @Test func withoutOneTheConnectionsActiveProfileIsUsed() async throws {
        let (client, socket) = try await connectedClient()
        await client.setProfile("research")
        _ = try await NewServerChat.start(using: client, profile: nil)
        #expect(socket.requests("session.create").last?.params?["profile"] as? String == "research")
        await client.setProfile(nil)
        _ = try await NewServerChat.start(using: client, profile: nil)
        #expect(socket.requests("session.create").last?.params?["profile"] == nil)
        await client.stop()
    }

    @Test func aServerErrorComesBackAsARefusal() async throws {
        let (client, socket) = try await connectedClient()
        socket.setResponder { frame in
            guard let id = frame.id, frame.method == "session.create" else { return [] }
            return [Frames.error(id: id, code: 4000, message: "no such profile")]
        }
        await #expect(throws: NewChatFailure.refused(reason: "no such profile")) {
            _ = try await NewServerChat.start(using: client, profile: "ghost")
        }
        await client.stop()
    }

    @Test func aStoppedClientMeansNotReachable() async throws {
        let (client, _) = try await connectedClient()
        await client.stop()
        await #expect(throws: NewChatFailure.notReachable) {
            _ = try await NewServerChat.start(using: client, profile: nil)
        }
    }
}

@Suite struct ConnectWaitTests {
    private let summary = ServerSummary()

    @Test func aConnectedServerIsAskedAtOnce() {
        #expect(ConnectWait.next(phase: .connected(summary), waited: 0) == .proceed)
        #expect(ConnectWait.next(phase: .connected(summary), waited: ConnectWait.patience + 5) == .proceed)
    }

    @Test func aServerThatIsConnectingIsWaitedForUntilPatienceRunsOut() {
        let busy: [ConnectionPhase] = [
            .idle, .unlocking, .openingTunnel, .checkingServer, .connecting, .reconnecting(attempt: 2),
        ]
        for phase in busy {
            #expect(ConnectWait.next(phase: phase, waited: 1) == .wait, "\(phase)")
            #expect(ConnectWait.next(phase: phase, waited: ConnectWait.patience - 1) == .wait, "\(phase)")
            #expect(ConnectWait.next(phase: phase, waited: ConnectWait.patience) == .giveUp, "\(phase)")
        }
    }

    @Test func aServerOnlyTheUserCanFixIsGivenUpAtOnce() {
        let stuck: [ConnectionPhase] = [
            .signInRequired, .updateRequired(found: "release 2026.1.1"), .failed(.notHermes),
        ]
        for phase in stuck {
            #expect(ConnectWait.next(phase: phase, waited: 0) == .giveUp, "\(phase)")
        }
    }
}

@Suite struct StartedChatsTests {
    @Test func aNewChatSurvivesListRefreshesUntilTheServerListsIt() {
        var started = StartedChats()
        started.note("s9")
        #expect(started.kept(among: ["s9", "s1"], listed: ["s1"]) == ["s9"])
        #expect(started.kept(among: ["s9", "s1"], listed: ["s1"]) == ["s9"], "a second refresh keeps it too")
        #expect(started.kept(among: ["s9", "s1"], listed: ["s1", "s9"]).isEmpty, "listed: the server owns it now")
    }

    @Test func aChatTheServerListedAndThenDroppedDoesNotComeBack() {
        var started = StartedChats()
        started.note("s9")
        #expect(started.kept(among: ["s9"], listed: ["s9"]).isEmpty)
        #expect(started.kept(among: ["s9"], listed: []).isEmpty, "deleted on the server")
    }

    @Test func aChatTheAppNoLongerShowsIsForgotten() {
        var started = StartedChats()
        started.note("s9")
        #expect(started.kept(among: ["s1"], listed: ["s1"]).isEmpty)
        #expect(started.kept(among: ["s9", "s1"], listed: ["s1"]).isEmpty, "forgotten for good")
    }

    @Test func onlyChatsTheAppMadeAreKept() {
        var started = StartedChats()
        #expect(started.kept(among: ["s1", "s2"], listed: []).isEmpty, "an unlisted chat that was not made here")
        started.note("s2")
        #expect(started.kept(among: ["s1", "s2"], listed: ["s1"]) == ["s2"])
    }
}
