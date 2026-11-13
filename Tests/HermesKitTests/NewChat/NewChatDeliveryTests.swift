import Foundation
import Testing

@testable import HermesKit

/// Makes sessions from a script and records every call, so a test can say how many were made and in what state the
/// outbox was when each was made.
private actor ScriptedCreator: NewChatCreator {
    private var script: [Result<String, NewChatCreateError>]
    private(set) var calls = 0
    private let seen: @Sendable () async -> Int
    private(set) var recordsSeenAtEachCall: [Int] = []
    private var delay = false

    /// `seen` counts the records the outbox holds, so a test can prove the message was written before the create.
    init(
        _ script: [Result<String, NewChatCreateError>] = [.success("sess-1")], seen: @escaping @Sendable () async -> Int
    ) {
        self.script = script
        self.seen = seen
    }

    func slow(_ enabled: Bool) { delay = enabled }

    func createSession() async throws -> String {
        calls += 1
        recordsSeenAtEachCall.append(await seen())
        while delay { try await Task.sleep(for: .milliseconds(2)) }
        let next = script.count > 1 ? script.removeFirst() : script[0]
        return try next.get()
    }
}

private actor StatusBox {
    var value: PillState = .connected
    func set(_ next: PillState) { value = next }
}

struct NewChatDeliveryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let serverA = "A-0000"
    private let serverB = "B-0000"

    private struct Rig {
        let cache: HermesCache
        let placeholder: PlaceholderChat
        let creator: ScriptedCreator
        let status: StatusBox
        let delivery: NewChatDelivery
    }

    private func rig(
        script: [Result<String, NewChatCreateError>] = [.success("sess-1")], connection: String? = nil,
        cache: HermesCache? = nil, placeholder existing: PlaceholderChat? = nil
    ) async throws -> Rig {
        let cache = try cache ?? HermesCache()
        let placeholder =
            existing
            ?? PlaceholderChat(
                id: "new-TEST", connectionID: connection ?? serverA, serverName: "Office Mac", createdAt: start)
        if try await cache.placeholders.placeholder(id: placeholder.id) == nil {
            try await cache.placeholders.insert(placeholder)
        }
        let outbox = cache.outbox
        let creator = ScriptedCreator(script, seen: { (try? await outbox.records(inChat: placeholder.id).count) ?? -1 })
        let status = StatusBox()
        let delivery = NewChatDelivery(
            placeholder: placeholder, placeholders: cache.placeholders, outbox: outbox, creator: creator,
            status: { await status.value }, clock: { Date(timeIntervalSince1970: 1_800_000_000) })
        return Rig(cache: cache, placeholder: placeholder, creator: creator, status: status, delivery: delivery)
    }

    private func texts(_ cache: HermesCache, chat: String) async throws -> [String] {
        try await cache.outbox.records(inChat: chat).map { "\($0.text):\($0.state.kind)" }
    }

    // N-L1: the message is written before any connect or create; a crash at every step leaves it waiting or delivered.
    @Test func theMessageIsSavedBeforeTheSessionIsCreated() async throws {
        let rig = try await rig()
        try await rig.delivery.enqueue("hello")
        #expect(await rig.creator.recordsSeenAtEachCall == [1])
    }

    @Test func aCrashAtEveryStepNeverLosesTheMessage() async throws {
        // Step 1, after the write and before the create: a fresh delivery over the same stores creates once and moves it.
        let first = try await rig()
        try await first.cache.outbox.insert(
            OutboundRecord(connectionID: serverA, chatID: "new-TEST", text: "hello", createdAt: start))
        let relaunched = try await rig(cache: first.cache, placeholder: first.placeholder)
        await relaunched.delivery.deliver()
        #expect(try await texts(first.cache, chat: "sess-1") == ["hello:pending"])
        #expect(try await texts(first.cache, chat: "new-TEST").isEmpty)

        // Step 2, after the session id was saved and before the move: the saved id is reused, nothing is created.
        let second = try await rig()
        try await second.cache.outbox.insert(
            OutboundRecord(connectionID: serverA, chatID: "new-TEST", text: "hi", createdAt: start))
        try await second.cache.placeholders.setSessionID("sess-9", forPlaceholder: "new-TEST")
        let after = try await rig(cache: second.cache, placeholder: second.placeholder)
        await after.delivery.deliver()
        #expect(await after.creator.calls == 0)
        #expect(try await texts(second.cache, chat: "sess-9") == ["hi:pending"])
    }

    // N-L2: waiting for the server, then connected: exactly one session, even with three triggers at once.
    @Test func threeTriggersAtOnceMakeOneSession() async throws {
        let rig = try await rig()
        await rig.creator.slow(true)
        try await rig.cache.outbox.insert(
            OutboundRecord(connectionID: serverA, chatID: "new-TEST", text: "hello", createdAt: start))

        async let one = rig.delivery.deliver()
        async let two = rig.delivery.deliver()
        async let three = rig.delivery.deliver()
        while await rig.creator.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
        await rig.creator.slow(false)
        _ = await (one, two, three)

        #expect(await rig.creator.calls == 1)
        #expect(await rig.delivery.state == .created(sessionID: "sess-1"))
        #expect(try await texts(rig.cache, chat: "sess-1") == ["hello:pending"])
    }

    // N-L3: the session id is saved before the messages move, and a relaunch with a saved id never creates again.
    @Test func theSessionIdIsSavedBeforeTheMessagesMove() async throws {
        let rig = try await rig()
        try await rig.delivery.enqueue("hello")
        #expect(try await rig.cache.placeholders.placeholder(id: "new-TEST")?.sessionID == "sess-1")
    }

    @Test func aRelaunchWithASavedSessionIdRebindsWithoutCreatingAgain() async throws {
        let first = try await rig()
        try await first.delivery.enqueue("hello")
        let relaunched = try await rig(cache: first.cache, placeholder: first.placeholder)
        await relaunched.delivery.deliver()
        #expect(await relaunched.creator.calls == 0)
        #expect(await relaunched.delivery.state == .created(sessionID: "sess-1"))
    }

    // N-L4: a refusal keeps the text as a failed row; a network loss goes back to waiting.
    @Test func aRefusalKeepsTheTextAsAFailedMessageAndRetryDeliversOnce() async throws {
        let rig = try await rig(script: [.failure(.refused("No such profile.")), .success("sess-2")])
        let state = try await rig.delivery.enqueue("hello")
        let shown = "Couldn't start the chat on Office Mac. No such profile."
        #expect(state == .createFailed(reason: shown))
        let records = try await rig.cache.outbox.records(inChat: "new-TEST")
        #expect(records.map(\.text) == ["hello"])
        #expect(records.first?.state == .failed(reason: shown))
        #expect(try await rig.cache.placeholders.placeholder(id: "new-TEST")?.sessionID == nil)

        await rig.delivery.retry()
        #expect(await rig.creator.calls == 2)
        #expect(try await texts(rig.cache, chat: "sess-2") == ["hello:pending"])
    }

    @Test func aLostConnectionDuringCreateGoesBackToWaitingNotFailed() async throws {
        let rig = try await rig(script: [.failure(.unreachable), .success("sess-3")])
        #expect(try await rig.delivery.enqueue("hello") == .waitingForServer)
        #expect(try await texts(rig.cache, chat: "new-TEST") == ["hello:pending"])

        await rig.delivery.deliver()
        #expect(try await texts(rig.cache, chat: "sess-3") == ["hello:pending"])
    }

    // N-L5: three messages queued in one placeholder keep their order.
    @Test func threeMessagesKeepTheirOrder() async throws {
        let rig = try await rig()
        await rig.status.set(.unreachable)
        for text in ["one", "two", "three"] { try await rig.delivery.enqueue(text) }
        #expect(await rig.creator.calls == 0)
        await rig.status.set(.connected)
        await rig.delivery.deliver()
        #expect(try await texts(rig.cache, chat: "sess-1") == ["one:pending", "two:pending", "three:pending"])
        #expect(await rig.creator.calls == 1)
    }

    // N-L6: a placeholder bound to server A never uses another server, and moves only its own records.
    @Test func aPlaceholderBoundToAMovesOnlyItsOwnServersMessages() async throws {
        let rig = try await rig()
        // Server B has a waiting message under the same chat id.
        try await rig.cache.outbox.insert(
            OutboundRecord(connectionID: serverB, chatID: "new-TEST", text: "for B", createdAt: start))
        try await rig.delivery.enqueue("for A")
        #expect(try await rig.cache.outbox.records(inChat: "sess-1").map(\.connectionID) == [serverA])
        let left = try await rig.cache.outbox.records(inChat: "new-TEST")
        #expect(left.map(\.connectionID) == [serverB])
        #expect(left.map(\.text) == ["for B"])
    }

    // N-L7: nothing is created or sent while the bound server is not connected.
    @Test func nothingIsCreatedWhileTheServerIsNotConnected() async throws {
        let rig = try await rig()
        let down: [PillState] = [
            .unreachable, .connecting, .reconnecting, .noServer, .needsAttention(.signIn),
        ]
        for pill in down {
            await rig.status.set(pill)
            #expect(try await rig.delivery.enqueue("while \(pill)") == .waitingForServer, "\(pill)")
        }
        #expect(await rig.creator.calls == 0)
        #expect(try await rig.cache.placeholders.placeholder(id: "new-TEST")?.sessionID == nil)
        #expect(try await rig.cache.outbox.records(inChat: "new-TEST").count == down.count)
    }

    @Test func anEmptyPlaceholderMakesNoSession() async throws {
        let rig = try await rig()
        #expect(await rig.delivery.deliver() == .empty)
        #expect(await rig.creator.calls == 0)
    }
}

struct PlaceholderStoreTests {
    @Test func aPlaceholderSurvivesARelaunchWithItsServerAndSession() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("placeholder-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        let chat = PlaceholderChat(
            id: "new-1", connectionID: "A", serverName: "Office Mac",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        do {
            let cache = try HermesCache(url: url)
            try await cache.placeholders.insert(chat)
            try await cache.placeholders.setSessionID("sess", forPlaceholder: "new-1")
        }
        let relaunched = try HermesCache(url: url)
        let found = try #require(try await relaunched.placeholders.all().first)
        #expect(found.id == "new-1")
        #expect(found.connectionID == "A")
        #expect(found.serverName == "Office Mac")
        #expect(found.sessionID == "sess")
    }

    @Test func purgingAServerForgetsItsPlaceholders() async throws {
        let cache = try HermesCache()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await cache.placeholders.insert(
            PlaceholderChat(id: "new-1", connectionID: "A", serverName: "A", createdAt: now))
        try await cache.placeholders.insert(
            PlaceholderChat(id: "new-2", connectionID: "B", serverName: "B", createdAt: now))
        try await cache.purge(connection: "A")
        #expect(try await cache.placeholders.all().map(\.id) == ["new-2"])
    }

    @Test func rebindKeepsOrderAndStatesAndIsScopedToItsConnection() async throws {
        let cache = try HermesCache()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for text in ["a", "b"] {
            try await cache.outbox.insert(
                OutboundRecord(connectionID: "A", chatID: "new-1", text: text, createdAt: now))
        }
        try await cache.outbox.insert(OutboundRecord(connectionID: "B", chatID: "new-1", text: "x", createdAt: now))
        let moved = try await cache.outbox.rebind(chat: "new-1", to: "sess", connection: "A")
        #expect(moved == 2)
        #expect(try await cache.outbox.records(inChat: "sess").map(\.text) == ["a", "b"])
        #expect(try await cache.outbox.records(inChat: "sess").allSatisfy { $0.chatID == "sess" })
        #expect(try await cache.outbox.records(inChat: "new-1").map(\.text) == ["x"])
    }
}
