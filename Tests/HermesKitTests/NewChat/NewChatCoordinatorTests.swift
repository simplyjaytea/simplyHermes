import Foundation
import Testing

@testable import HermesKit

private actor CountingCreator: NewChatCreator {
    private var next = 0
    private(set) var calls = 0
    private let prefix: String
    init(prefix: String = "sess") { self.prefix = prefix }
    func createSession() async throws -> String {
        calls += 1
        next += 1
        return "\(prefix)-\(next)"
    }
}

private actor Announcements {
    private(set) var created: [(placeholder: String, session: String)] = []
    func note(_ placeholder: String, _ session: String) { created.append((placeholder, session)) }
}

private actor PillBox {
    var value: PillState = .unreachable
    func set(_ next: PillState) { value = next }
}

struct NewChatCoordinatorTests {
    private struct Rig {
        let cache: HermesCache
        let coordinator: NewChatCoordinator
        let creatorA: CountingCreator
        let announced: Announcements
        let pillA: PillBox
    }

    private func rig(cache: HermesCache? = nil, pillA: PillBox = PillBox()) throws -> Rig {
        let cache = try cache ?? HermesCache()
        let creatorA = CountingCreator()
        let announced = Announcements()
        let coordinator = NewChatCoordinator(
            placeholders: cache.placeholders, outbox: cache.outbox,
            creator: { $0 == "A" ? creatorA : nil },
            status: { $0 == "A" ? await pillA.value : .noServer },
            onCreated: { placeholder, session in await announced.note(placeholder.id, session) })
        return Rig(cache: cache, coordinator: coordinator, creatorA: creatorA, announced: announced, pillA: pillA)
    }

    @Test func aMessageSentWhileTheServerIsDownWaitsAndGoesOutOnceWhenItIsBack() async throws {
        let rig = try rig()
        let chat = try await rig.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
        #expect(try await rig.coordinator.send("hello", in: chat.id) == .waitingForServer)
        #expect(try await rig.coordinator.waiting(in: chat.id).map(\.text) == ["hello"])
        #expect(await rig.creatorA.calls == 0)

        await rig.pillA.set(.connected)
        await rig.coordinator.serverMayBeBack(connectionID: "A")
        await rig.coordinator.serverMayBeBack(connectionID: "A")  // a second trigger changes nothing

        #expect(await rig.creatorA.calls == 1)
        let announced = await rig.announced.created
        #expect(announced.count == 1)
        #expect(announced.first?.placeholder == chat.id)
        let session = try #require(announced.first?.session)
        #expect(try await rig.cache.outbox.records(inChat: session).map(\.text) == ["hello"])
        #expect(try await rig.cache.placeholders.all().isEmpty)
    }

    @Test func aMessageSentWhileConnectedCreatesTheChatAtOnce() async throws {
        let rig = try rig(pillA: PillBox())
        await rig.pillA.set(.connected)
        let chat = try await rig.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
        try await rig.coordinator.send("hello", in: chat.id)
        #expect(await rig.announced.created.count == 1)
        #expect(await rig.creatorA.calls == 1)
    }

    @Test func aWaitingMessageSurvivesARelaunchAndGoesOutOnceWhenTheServerIsBack() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        let chatID: String
        do {
            let first = try rig(cache: try HermesCache(url: url))
            let chat = try await first.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
            try await first.coordinator.send("outage test", in: chat.id)
            chatID = chat.id
        }
        // Relaunched with the server still down: the row and its waiting message come back, nothing is sent.
        let down = try rig(cache: try HermesCache(url: url))
        let restored = try await down.coordinator.restore()
        #expect(restored.map(\.id) == [chatID])
        #expect(restored.first?.serverName == "Office Mac")
        #expect(try await down.coordinator.waiting(in: chatID).map(\.text) == ["outage test"])
        #expect(await down.creatorA.calls == 0)

        // Relaunched again with the server connected: delivered once.
        let connectedPill = PillBox()
        await connectedPill.set(.connected)
        let back = try rig(cache: try HermesCache(url: url), pillA: connectedPill)
        _ = try await back.coordinator.restore()
        #expect(await back.creatorA.calls == 1)
        #expect(await back.announced.created.count == 1)
    }

    @Test func twoPlaceholdersOnOneServerEachMakeOneChatInTheOrderTheyWereSent() async throws {
        let rig = try rig()
        let one = try await rig.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
        try await rig.coordinator.send("first", in: one.id)
        let two = try await rig.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
        try await rig.coordinator.send("second", in: two.id)

        await rig.pillA.set(.connected)
        await rig.coordinator.serverMayBeBack(connectionID: "A")

        #expect(await rig.creatorA.calls == 2)
        #expect(await rig.announced.created.map(\.placeholder) == [one.id, two.id])
    }

    @Test func aPlaceholderBoundToAServerThatIsNoLongerSavedKeepsItsMessage() async throws {
        let rig = try rig()
        let chat = try await rig.coordinator.makePlaceholder(connectionID: "Z", serverName: "Gone")
        let state = try await rig.coordinator.send("hello", in: chat.id)
        #expect(state == .createFailed(reason: "This server is no longer saved."))
        // Nothing could carry the text, so nothing was saved or sent. The screen keeps it in the composer.
        #expect(try await rig.coordinator.waiting(in: chat.id).isEmpty)
        #expect(await rig.creatorA.calls == 0)
    }

    @Test func aServerChangeNeverMovesAPlaceholderToAnotherServer() async throws {
        let rig = try rig()
        let chat = try await rig.coordinator.makePlaceholder(connectionID: "A", serverName: "Office Mac")
        try await rig.coordinator.send("hello", in: chat.id)
        // Another server comes up. Only A's trigger can deliver this placeholder.
        await rig.pillA.set(.connected)
        await rig.coordinator.serverMayBeBack(connectionID: "B")
        #expect(await rig.creatorA.calls == 0)
        #expect(await rig.announced.created.isEmpty)
    }

    @Test func aPlaceholderMadeInMemoryIsSavedOnlyWhenItIsFirstUsed() async throws {
        let rig = try rig()
        let chat = PlaceholderChat(connectionID: "A", serverName: "Office Mac", createdAt: Date())
        #expect(try await rig.cache.placeholders.all().isEmpty)
        try await rig.coordinator.ensureSaved(chat)
        try await rig.coordinator.ensureSaved(chat)
        #expect(try await rig.cache.placeholders.all().map(\.id) == [chat.id])
    }
}
