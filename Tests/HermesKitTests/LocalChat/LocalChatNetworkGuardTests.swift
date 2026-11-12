import Foundation
import GRDB
import Testing

@testable import HermesKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// G2: local chats never use the network (user rule). Two guards, proposal G2 in
// Shared/simplyhermes-gilfoyle-proposals-2026-11-02.md:
// 1. A source lint with zero exceptions over the local-chat files: no networking type, client or module is named there.
//    A listed file that goes missing fails too, so a rename cannot quietly empty the scan.
// 2. AT-2 at runtime: a real local turn (send, reply, relaunch, send) opens no connection at all, counted by NetworkTrap
//    across every transport, with a positive control in the same run.

/// The source lint.
enum LocalChatNetworkGuard {
    /// Every file of the local-chat feature, relative to the repository root. Not `Sources/HermesKit/OnDeviceModels/`:
    /// the model downloader uses the network by design, and only the answer path is guarded here.
    static let files = [
        "Sources/HermesKit/LocalChat/ChatModeDefault.swift",
        "Sources/HermesKit/LocalChat/LocalChat.swift",
        "Sources/HermesKit/LocalChat/LocalChatAnswerer.swift",
        "Sources/HermesKit/LocalChat/LocalChatController.swift",
        "Sources/HermesKit/LocalChat/LocalChatStore.swift",
        "Sources/HermesKit/LocalChat/LocalMemory.swift",
        "Sources/HermesUI/LocalChat/LocalChatModel.swift",
        "Sources/HermesUI/LocalChat/LocalChatScreen.swift",
        "Sources/HermesUI/LocalChat/LocalChatServices.swift",
        "App/HermesApp/LocalChat/UITestSeams.swift",
    ]

    /// Names that only network code uses. Matched as words, so `URLSessionHTTPTransport` counts as `URLSession`.
    static let forbidden = [
        "URLSession", "URLRequest", "URLProtocol", "GatewayClient", "ChatTransport", "HTTPTransport", "WebSocket",
        "Citadel", "NIOCore", "NIOPosix", "NIOHTTP1", "NIOWebSocket", "NIOSSH", "SendToHermes", "HermesSSH",
        "FoundationNetworking",
    ]

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Each forbidden name on a code line of `text`, as `path:line: name`. Comments are not code.
    static func violations(path: String, text: String) -> [String] {
        text.components(separatedBy: "\n").enumerated().flatMap { index, line -> [String] in
            let code = line.components(separatedBy: "//").first ?? ""
            return forbidden.filter { code.contains($0) }.map { "\(path):\(index + 1): \($0)" }
        }
    }

    /// The listed files that do not exist under `root`.
    static func missing(_ list: [String], under root: URL) -> [String] {
        list.filter { !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    /// The folders that hold only local-chat code. Every Swift file in them must be in ``files``.
    static let folders = ["Sources/HermesKit/LocalChat", "Sources/HermesUI/LocalChat", "App/HermesApp/LocalChat"]

    /// The Swift files in `folders` under `root` that ``files`` does not list, as repository paths.
    static func unlisted(in folders: [String], under root: URL, listed: [String]) -> [String] {
        let manager = FileManager.default
        let found = folders.flatMap { folder -> [String] in
            let url = root.appendingPathComponent(folder)
            guard let walker = manager.enumerator(atPath: url.path) else { return [] }
            return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.map { "\(folder)/\($0)" }
        }
        return Set(found).subtracting(listed).sorted()
    }
}

struct LocalChatNetworkGuardTests {
    @Test func everyLocalChatFileIsStillThere() {
        let missing = LocalChatNetworkGuard.missing(LocalChatNetworkGuard.files, under: LocalChatNetworkGuard.repoRoot)
        #expect(missing.isEmpty, "Moved or deleted local-chat files must be updated in the guard's list: \(missing)")
    }

    @Test func everyFileInTheLocalChatFoldersIsListed() {
        let guardRoot = LocalChatNetworkGuard.repoRoot
        let unlisted = LocalChatNetworkGuard.unlisted(
            in: LocalChatNetworkGuard.folders, under: guardRoot, listed: LocalChatNetworkGuard.files)
        #expect(unlisted.isEmpty, "Add new local-chat files to the guard's list, so they are scanned: \(unlisted)")
    }

    @Test func aNewFileInALocalChatFolderIsCaught() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sources/HermesKit/LocalChat")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["LocalChat.swift", "Sneaky.swift"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let unlisted = LocalChatNetworkGuard.unlisted(
            in: ["Sources/HermesKit/LocalChat"], under: root, listed: ["Sources/HermesKit/LocalChat/LocalChat.swift"])
        #expect(unlisted == ["Sources/HermesKit/LocalChat/Sneaky.swift"])
    }

    @Test func noLocalChatFileNamesTheNetwork() throws {
        var found: [String] = []
        for path in LocalChatNetworkGuard.files {
            let url = LocalChatNetworkGuard.repoRoot.appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found += LocalChatNetworkGuard.violations(path: path, text: text)
        }
        #expect(found.isEmpty, "Local chats must never use the network: \(found)")
    }

    @Test(arguments: LocalChatNetworkGuard.forbidden)
    func eachForbiddenNameIsCaught(name: String) {
        let text = "import Foundation\nlet planted = \(name)(configuration: .default)\n"
        // `NIOWebSocket` also matches `WebSocket`, so check that this name is among the hits.
        #expect(LocalChatNetworkGuard.violations(path: "X.swift", text: text).contains("X.swift:2: \(name)"))
    }

    @Test func aPlantedSessionInAListedFileIsCaught() throws {
        let path = "Sources/HermesKit/LocalChat/LocalChatController.swift"
        let real = try String(contentsOf: LocalChatNetworkGuard.repoRoot.appendingPathComponent(path), encoding: .utf8)
        let planted = real + "\nlet leak = URLSession.shared\n"
        #expect(LocalChatNetworkGuard.violations(path: path, text: planted).count == 1)
    }

    @Test func aMissingListedFileIsCaught() {
        let list = LocalChatNetworkGuard.files + ["Sources/HermesKit/LocalChat/Renamed.swift"]
        #expect(
            LocalChatNetworkGuard.missing(list, under: LocalChatNetworkGuard.repoRoot)
                == ["Sources/HermesKit/LocalChat/Renamed.swift"])
    }

    @Test func aNameInACommentIsNotCode() {
        let text = "// This file never touches URLSession.\nlet x = 1\n"
        #expect(LocalChatNetworkGuard.violations(path: "X.swift", text: text).isEmpty)
    }
}

/// AT-2 at runtime. NetworkTrap counts every connection the process opens, so the zero is exact only when nothing else
/// runs: CI runs this suite alone, in its own step, with `HERMES_NETWORK_ISOLATION=1`. It is skipped in the full suite.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["HERMES_NETWORK_ISOLATION"] == "1", "needs a process of its own"))
struct LocalChatNetworkIsolationTests {
    private let closed = URL(string: "http://127.0.0.1:9/")!

    /// The positive control: the trap counts a real request in this process, so the zero below means something.
    @Test func theTrapCountsARequest() async throws {
        let before = NetworkTrap.count
        _ = try? await URLSessionHTTPTransport(timeout: 2).send(HTTPRequest(method: "GET", url: closed, timeout: 2))
        #expect(NetworkTrap.count > before, "NetworkTrap missed an HTTP request: \(NetworkTrap.summary)")
    }

    /// A real local turn, a relaunch and a second turn open no connection of any kind: no HTTP, no WebSocket, so no
    /// gateway, no terminal, no SSH, no download, and nothing a factory session would intercept.
    @Test func aLocalTurnAndARelaunchOpenNoConnection() async throws {
        let before = NetworkTrap.summary
        let start = NetworkTrap.count
        let url = try temporaryDatabaseURL()
        let id = UUID()
        let answerer = FixedModelAnswerer(identity: .apple, executor: ScriptedExecutor(.reply("on-device reply")))
        do {
            let controller = await LocalChatController(
                store: try HermesCache(url: url).localChats, answerer: { answerer }, chatID: id, now: { localChatStart }
            )
            await controller.send("first question")
            #expect(await controller.snapshot.messages.map(\.text) == ["first question", "on-device reply"])
        }
        let reopened = GRDBLocalChatStore(database: try DatabaseQueue(path: url.path))
        let controller = await LocalChatController(
            store: reopened, answerer: { answerer }, chatID: id, now: { localChatStart })
        await controller.send("second question")
        #expect(await controller.snapshot.messages.count == 4)

        #expect(NetworkTrap.count == start, "A local chat opened a connection: \(before) -> \(NetworkTrap.summary)")
    }
}
