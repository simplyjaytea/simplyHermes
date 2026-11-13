import Foundation
import HermesKit
import HermesUI
import Testing

/// Review m3 on #131: the app's wiring of local-chat memory. HermesUI compiles only on macOS, so this runs in the
/// App job: removing the `memory:` hook in `LocalChatModel` or the store in `LocalChatServices.install` fails it.
@MainActor
struct LocalMemoryWiringTests {
    private final class Recorder: LocalChatAnswerer, @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        var availability: LocalModelAvailability { .available }
        var instructions: [String] { lock.withLock { seen } }

        func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
            lock.withLock { seen.append(instructions) }
            return LocalAnswer(text: "ok", answeredBy: .apple)
        }
    }

    @Test func installedServicesCarryTheMemoryStore() throws {
        let cache = try HermesCache()
        let recorder = Recorder()
        LocalChatServices.install(cache: cache, answerer: { recorder })
        defer { LocalChatServices.shared = nil }
        #expect(LocalChatServices.shared?.memory != nil)
    }

    @Test func aLocalChatReplyIsAskedWithTheSavedMemory() async throws {
        let cache = try HermesCache()
        try await cache.localMemory.save("I'm vegetarian", source: .user, at: Date())
        let recorder = Recorder()
        LocalChatServices.install(cache: cache, answerer: { recorder })
        defer { LocalChatServices.shared = nil }
        let services = try #require(LocalChatServices.shared)
        let chat = LocalChatModel(chatID: UUID(), services: services)
        #expect(await chat.submit("Dinner ideas?"))
        for _ in 0..<100 where recorder.instructions.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(recorder.instructions.first?.contains("- I'm vegetarian") == true)
    }
}
