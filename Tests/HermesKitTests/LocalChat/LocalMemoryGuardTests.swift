import Foundation
import Testing

@testable import HermesKit

/// Local agent abilities, phase 1 guards (spec section 7): on-device memory imports nothing that could reach the
/// network, and no server-chat code can read it, so it can never be sent to a server.
struct LocalMemoryGuardTests {
    static let memoryFiles = ["Sources/HermesKit/LocalChat/LocalMemory.swift"]
    static let allowedImports: Set<String> = ["Foundation", "GRDB"]
    /// Code that talks to a server. None of it may name local memory.
    static let serverFolders = [
        "Sources/HermesKit/Chat", "Sources/HermesKit/Transport", "Sources/HermesKit/Outbox", "Sources/HermesKit/REST",
        "Sources/HermesKit/Connection", "Sources/HermesUI/Chat", "Sources/HermesUI/Delivery",
    ]
    static let memoryNames = ["LocalMemory", "localMemory", "local_memory"]

    /// The modules `text` imports, also behind attributes (`@preconcurrency import Network`) or a kind
    /// (`import struct Network.NWConnection`).
    static func imports(in text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line in
            let words = (line.components(separatedBy: "//").first ?? "").split(whereSeparator: \.isWhitespace)
            guard words.contains("import"), let module = words.last, module != "import" else {
                return nil
            }
            return module.split(separator: ".").first.map(String.init)
        }
    }

    static func mentions(in folders: [String], under root: URL) -> [String] {
        folders.flatMap { folder -> [String] in
            let url = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(atPath: url.path) else { return [] }
            return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.flatMap { file -> [String] in
                let text = (try? String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)) ?? ""
                return memoryNames.filter { text.contains($0) }.map { "\(folder)/\(file): \($0)" }
            }
        }
    }

    @Test func memoryImportsOnlyFoundationAndGRDB() throws {
        for path in Self.memoryFiles {
            let text = try String(
                contentsOf: LocalChatNetworkGuard.repoRoot.appendingPathComponent(path), encoding: .utf8)
            let extra = Set(Self.imports(in: text)).subtracting(Self.allowedImports)
            #expect(extra.isEmpty, "\(path) imports \(extra.sorted())")
        }
    }

    @Test func theImportCheckCatchesANetworkImport() {
        #expect(Self.imports(in: "import Foundation\n@preconcurrency import Network\n") == ["Foundation", "Network"])
        #expect(Self.imports(in: "import struct Network.NWConnection") == ["Network"])
        #expect(Self.imports(in: "// import Network") == [])
    }

    @Test func noServerChatCodeNamesLocalMemory() {
        let found = Self.mentions(in: Self.serverFolders, under: LocalChatNetworkGuard.repoRoot)
        #expect(found.isEmpty, "Local memory must never reach server-chat code: \(found)")
    }

    @Test func theServerCodeScanCatchesAMention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sources/HermesKit/Chat")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("let notes = cache.localMemory".utf8).write(to: folder.appendingPathComponent("Leak.swift"))
        #expect(
            Self.mentions(in: ["Sources/HermesKit/Chat"], under: root) == [
                "Sources/HermesKit/Chat/Leak.swift: localMemory"
            ])
    }

    @Test func theServerFoldersExist() {
        let missing = Self.serverFolders.filter {
            !FileManager.default.fileExists(atPath: LocalChatNetworkGuard.repoRoot.appendingPathComponent($0).path)
        }
        #expect(missing.isEmpty, "A renamed folder would make the scan pass by finding nothing: \(missing)")
    }
}
