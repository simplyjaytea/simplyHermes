import HermesKit
import Testing

@testable import HermesUI

/// WP-3: a typed message is saved to the outbox before anything else, and the composer may clear only after that.
/// These run with no server, so the message stays "Waiting to send".
@MainActor
struct LiveChatSendTests {
    private func chat(_ cache: HermesCache) -> LiveChatModel {
        let services = ConnectionServices(credentials: InMemoryCredentialStore(), unlocker: AlwaysUnlocked())
        let connections = ConnectionsModel(store: nil, services: services)
        return LiveChatModel(
            connections: connections, broker: ServerRequestBroker(), storedSessionID: "s1", outbox: cache.outbox)
    }

    @Test func aTypedMessageIsSavedAndWaits() async throws {
        let cache = try HermesCache()
        let model = chat(cache)

        #expect(await model.send("hello"))

        #expect(model.outboxRows.map(\.text) == ["hello"])
        #expect(try await cache.outbox.records(inChat: "s1").map(\.text) == ["hello"])
    }

    @Test func aFirstMessageIsSavedAtHandOffBeforeTheChatAttaches() async throws {
        let cache = try HermesCache()
        let model = chat(cache)

        model.queueFirstMessage("hello", attachments: [])

        // The save runs in a task. Wait for it, with a bound so a failure ends the test instead of hanging it.
        var shown = false
        for _ in 0..<200 {
            if !model.outboxRows.isEmpty {
                shown = true
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(shown)
        #expect(model.outboxRows.map(\.text) == ["hello"])
        #expect(try await cache.outbox.records(inChat: "s1").map(\.text) == ["hello"])
    }

    @Test func aBlankMessageIsNotSaved() async throws {
        let cache = try HermesCache()
        let model = chat(cache)

        #expect(await model.send("   ") == false)

        #expect(model.outboxRows.isEmpty)
        #expect(try await cache.outbox.records(inChat: "s1").isEmpty)
    }
}
