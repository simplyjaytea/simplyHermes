import Foundation
import Testing

/// The rules that keep every network connection counted (WP-7, AT-2b). Both checks take a path relative to `Sources/` and
/// the file's text, so the real tree and the test fixtures go through the same code.
///
/// 1. Sessions: `URLSession(`, `URLSession.init(` and `URLSession.shared` may appear only in the factory file. Every
///    other session must come from `NetworkSessions.make`, which puts the counting protocol first.
/// 2. Other openers (`ClientBootstrap(`, `NWConnection(`, `SSHClient.connect(`, ...): each occurrence needs its own
///    `NetworkTrap.record(` on one of the `window` lines above it, in the same function. A record covers only the next
///    opener after it, so a second unrecorded opener in a file that already records is a violation.
enum ConnectionGuard {
    /// The only file that may create a `URLSession`.
    static let factoryPath = "HermesKit/Diagnostics/NetworkSessions.swift"

    static let sessionOpeners = ["URLSession(", "URLSession.init(", "URLSession.shared"]

    static let connectionOpeners = [
        "ClientBootstrap(", "NIOTSConnectionBootstrap(", "NWConnection(", "SSHClient.connect(", "ServerBootstrap(",
    ]

    /// Lines above an opener that may hold its `NetworkTrap.record(`.
    static let window = 5

    /// Openers that open no outgoing connection, each with its reason. Keys are `path|opener`.
    static let exemptions: [String: String] = [
        "HermesSSH/LoopbackForwarder.swift|ServerBootstrap(":
            "Listens on loopback for the app's own SSH forwarding. It accepts no outgoing connection; the outgoing SSH "
            + "connection is counted at SSHClient.connect."
    ]

    /// Rule 1: session creation outside the factory.
    static func sessionViolations(path: String, text: String) -> [String] {
        guard path != factoryPath else { return [] }
        return text.components(separatedBy: "\n").enumerated().flatMap { index, line in
            sessionOpeners.filter { line.contains($0) }.map { opener in
                "\(path):\(index + 1): creates a URLSession (`\(opener)`) outside NetworkSessions.make"
            }
        }
    }

    /// Rule 2: each connection opener is recorded by its own record in the window above it, in the same function.
    static func openerViolations(path: String, text: String) -> [String] {
        var found: [String] = []
        var lastRecord: Int?
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if line.contains("func ") { lastRecord = nil }
            if line.contains("NetworkTrap.record(") { lastRecord = index }
            for opener in connectionOpeners where line.contains(opener) {
                if exemptions["\(path)|\(opener)"] != nil { continue }
                if let record = lastRecord, index - record <= window {
                    lastRecord = nil
                } else {
                    found.append(
                        "\(path):\(index + 1): `\(opener)` opens a connection with no NetworkTrap.record "
                            + "in the \(window) lines above it, in the same function")
                }
            }
        }
        return found
    }

    /// Both rules.
    static func violations(path: String, text: String) -> [String] {
        sessionViolations(path: path, text: text) + openerViolations(path: path, text: text)
    }

    /// Every Swift file under `Sources/` of this package, as (relative path, text).
    static func sourceFiles() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map { file in
            (String(file.path.dropFirst(sources.path.count + 1)), try String(contentsOf: file, encoding: .utf8))
        }
    }
}
