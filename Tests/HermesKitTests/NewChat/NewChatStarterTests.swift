import Foundation
import Testing

@testable import HermesKit

private actor Counter {
    private(set) var creates = 0
    private(set) var activeServer: String?
    init(active: String?) { activeServer = active }
    func create() -> String {
        creates += 1
        return "sess-\(creates)"
    }
    func switchTo(_ server: String?) { activeServer = server }
}

/// Row 143: a server switch during the first message's wait must not send the message to the other server.
struct NewChatStarterTests {
    @Test func theChatIsMadeOnTheServerTheMessageWasWrittenFor() async throws {
        let state = Counter(active: "A")
        let session = try await NewChatStarter.start(
            bound: "A", serverName: "Office Mac", active: { await state.activeServer }, wait: { true },
            create: { await state.create() })
        #expect(session == "sess-1")
    }

    @Test func aSwitchDuringTheWaitCreatesNothingAndThrows() async throws {
        let state = Counter(active: "A")
        await #expect(throws: NewChatServerChanged(serverName: "Office Mac")) {
            try await NewChatStarter.start(
                bound: "A", serverName: "Office Mac", active: { await state.activeServer },
                wait: {
                    await state.switchTo("B")  // the user switches while the server connects
                    return true
                }, create: { await state.create() })
        }
        #expect(await state.creates == 0)
    }

    @Test func aSwitchDuringTheCreateHandsNothingOn() async throws {
        let state = Counter(active: "A")
        await #expect(throws: NewChatServerChanged(serverName: "Office Mac")) {
            try await NewChatStarter.start(
                bound: "A", serverName: "Office Mac", active: { await state.activeServer }, wait: { true },
                create: {
                    await state.switchTo("B")
                    return await state.create()
                })
        }
        // The empty chat exists on A, but no session id came back, so nothing is adopted or sent.
        #expect(await state.creates == 1)
    }

    @Test func aServerThatDoesNotConnectIsNilAndCreatesNothing() async throws {
        let state = Counter(active: "A")
        let session = try await NewChatStarter.start(
            bound: "A", serverName: "Office Mac", active: { await state.activeServer }, wait: { false },
            create: { await state.create() })
        #expect(session == nil)
        #expect(await state.creates == 0)
    }

    @Test func aSwitchAndSwitchBackStillCountsAsAnswerForTheBoundServer() async throws {
        // Only the server at the moment of the check matters: it is the one the message goes to.
        let state = Counter(active: "A")
        let session = try await NewChatStarter.start(
            bound: "A", serverName: "Office Mac", active: { await state.activeServer },
            wait: {
                await state.switchTo("B")
                await state.switchTo("A")
                return true
            }, create: { await state.create() })
        #expect(session == "sess-1")
    }

    @Test func noActiveServerIsNotTheBoundServer() async throws {
        let state = Counter(active: nil)
        await #expect(throws: NewChatServerChanged.self) {
            try await NewChatStarter.start(
                bound: "A", serverName: "x", active: { await state.activeServer }, wait: { true },
                create: { await state.create() })
        }
    }
}
