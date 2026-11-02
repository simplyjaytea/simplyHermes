import Foundation
import Testing

@testable import HermesKit

/// The user's rules for local chats, checked where they can be checked on Linux (plan §3.3, AT-1 and AT-3).
struct LocalChatRulesTests {
    private static let serverChat = ChatBackend.server(
        connectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, profile: nil, sessionID: "s2")

    private static let phases: [ConnectionPhase?] = [
        nil, .idle, .connecting, .reconnecting(attempt: 2), .failed(.unreachable("no answer")),
        .signInRequired, .updateRequired(found: "0.9.0"),
    ]

    private static let gemmaModel = OnDeviceModelCatalog.standard.models[0]

    private static let locals: [LocalModelStatus] = [
        .off, .noModel, .notLoaded(gemmaModel), .loading(gemmaModel),
        .ready(answeredBy: .apple),
        .ready(answeredBy: .downloaded(id: gemmaModel.id, displayName: gemmaModel.displayName)),
        .failed(.apple, reason: .runtimeUnavailable),
    ]

    // AT-1: the offline router and the send-to-server offer are gone from the sources, so nothing can switch a chat.
    @Test func theAutomaticSwitchSymbolsAreGoneFromSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let banned = ["OfflineRouter", "OfflineRoute", "SendToHermes"]
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            scanned += 1
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in banned where text.contains(symbol) {
                Issue.record("\(symbol) still appears in \(file.lastPathComponent)")
            }
        }
        #expect(scanned > 0)
    }

    // AT-3: selecting a model or turning on-device features off never changes where a server chat's message goes.
    @Test func selectingAModelNeverChangesAServerChatsSendPath() {
        for phase in Self.phases {
            for path in [NetworkPath.unknown, .satisfied, .unsatisfied] {
                let results = Self.locals.map { local in
                    ChatStatusDeriver.derive(backend: Self.serverChat, phase: phase, path: path, local: local).sendPath
                }
                #expect(Set(results.map { "\($0)" }).count == 1, "phase \(String(describing: phase)), \(path)")
                #expect(
                    results.allSatisfy { result in
                        if case .local = result { false } else { true }
                    })
            }
        }
    }

    // AT-3: a local chat's messages live only in the local tables. A server chat's rows are untouched by them.
    @Test func aLocalChatLeavesTheServerTablesEmpty() async throws {
        let cache = try HermesCache()
        let controller = await LocalChatController(
            store: cache.localChats,
            answerer: { FixedModelAnswerer(identity: .apple, executor: ScriptedExecutor(.reply("local answer"))) },
            chatID: UUID(), now: { localChatStart })
        await controller.send("question")

        #expect(try await cache.sessions(connection: "any").isEmpty)
        #expect(try await cache.messageCount(sessionID: "s2", connection: "any") == 0)
        #expect(
            try await cache.localChats.messages(inChat: try #require(await controller.snapshot.chat?.id)).count == 2)
    }
}
