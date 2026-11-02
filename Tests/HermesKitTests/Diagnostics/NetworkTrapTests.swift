import Foundation
import Testing

@testable import HermesKit

/// The positive controls and the structural guard for the AT-2b trap. A zero that a local chat reports means something
/// only if every transport counts itself, so these tests fail when a transport is missed.
struct NetworkTrapTests {
    // A port nothing listens on, so the attempt fails at once and makes no real request.
    private let closed = URL(string: "http://127.0.0.1:9/")!

    @Test func anHTTPRequestIsCounted() async throws {
        let before = NetworkTrap.count(at: "http")
        _ = try? await URLSessionHTTPTransport(timeout: 2).send(HTTPRequest(method: "GET", url: closed, timeout: 2))
        #expect(NetworkTrap.count(at: "http") >= before + 1)
    }

    @Test func aModelDownloadIsCounted() async throws {
        let before = NetworkTrap.count(at: "download")
        let downloader = URLSessionModelFileDownloader()
        _ = try? await downloader.download(
            from: closed.appendingPathComponent("probe.bin"), resumeData: nil, progress: { _ in })
        #expect(NetworkTrap.count(at: "download") >= before + 1)
    }

    // Every file that opens a connection must record it. This reads the sources, so it runs on Linux too, where the
    // Apple-only WebSocket and terminal transports are still scanned as text. A transport added later and left
    // uncounted fails here.
    @Test func everyFileThatOpensAConnectionRecordsIt() throws {
        let sources = try sourceRoot()
        // Files that open a connection on purpose but are not app traffic. Each entry says why.
        let allowlist: [String: String] = [:]
        let openers = [
            "URLSession(", "URLSession.shared", "ClientBootstrap(", "SSHClient.connect(", "webSocketTask(with",
            "downloadTask(with", "dataTask(with",
        ]
        var scanned: [String] = []
        var unrecorded: [String] = []
        for file in try swiftFiles(under: sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard openers.contains(where: text.contains) else { continue }
            let relative = relativePath(of: file, to: sources)
            scanned.append(relative)
            if allowlist[relative] != nil { continue }
            if !text.contains("NetworkTrap.record(") { unrecorded.append(relative) }
        }
        #expect(scanned.count >= 4, "The scan should find the known transports, found \(scanned)")
        #expect(unrecorded.isEmpty, "These open a connection without NetworkTrap.record: \(unrecorded)")
    }

    // Every site a file records is one the readout lists, and every listed site is recorded somewhere, so the per-site
    // readout names only real transports.
    @Test func everyRecordedSiteIsAKnownSiteAndEverySiteIsRecorded() throws {
        let sources = try sourceRoot()
        var recorded: Set<String> = []
        for file in try swiftFiles(under: sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: #/NetworkTrap\.record\("([a-z]+)"\)/#) {
                recorded.insert(String(match.1))
            }
        }
        #expect(recorded.isSubset(of: Set(NetworkTrap.sites)), "Unknown site recorded: \(recorded)")
        #expect(
            Set(NetworkTrap.sites).isSubset(of: recorded),
            "Listed sites never recorded: \(Set(NetworkTrap.sites).subtracting(recorded))")
    }

    /// `Sources/` of this package, found from this file's path.
    private func sourceRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Sources", isDirectory: true)
    }

    private func swiftFiles(under folder: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func relativePath(of file: URL, to folder: URL) -> String {
        String(file.path.dropFirst(folder.path.count + 1))
    }
}
