import Foundation
import Testing

/// The rules that keep every network connection counted (WP-7, AT-2b). Both checks take a path relative to `Sources/` and
/// the file's text, so the real tree and the test fixtures go through the same code.
///
/// 1. Sessions: `URLSession(`, `URLSession.init(` and `URLSession.shared` may appear only in the factory file. Every
///    other session must come from `NetworkSessions.make`, which puts the counting protocol first. A `typealias` of
///    `URLSession` and an `extension URLSession` are refused outside the factory too, because they open the same door
///    under another name.
/// 2. Other openers (`ClientBootstrap(`, `NWConnection(`, `SSHClient.connect(`, ...): each occurrence needs its own
///    `NetworkTrap.record(` on one of the `window` lines above it, in the same function, and the record must be on the
///    opener's path: in the same block or one that encloses it. A record in a branch that has closed (the other arm of
///    an `if`, or a block that ended before the opener) does not count. A record covers only the next opener after it,
///    so a second unrecorded opener in a file that already records is a violation.
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

    /// Rule 1: session creation outside the factory, directly or through an alias or an extension.
    static func sessionViolations(path: String, text: String) -> [String] {
        guard path != factoryPath else { return [] }
        return text.components(separatedBy: "\n").enumerated().flatMap { index, line -> [String] in
            var found = sessionOpeners.filter { line.contains($0) }.map { opener in
                "\(path):\(index + 1): creates a URLSession (`\(opener)`) outside NetworkSessions.make"
            }
            if line.firstMatch(of: #/typealias\s+\w+\s*=\s*(?:Foundation\.)?URLSession(?:[^.\w]|$)/#) != nil {
                found.append("\(path):\(index + 1): aliases URLSession outside NetworkSessions.make")
            }
            if line.firstMatch(of: #/extension\s+(?:Foundation\.)?URLSession(?:[^.\w]|$)/#) != nil {
                found.append("\(path):\(index + 1): extends URLSession outside NetworkSessions.make")
            }
            return found
        }
    }

    /// Rule 2: each connection opener is recorded by its own record in the window above it, in the same function, on its
    /// path (the record's block is still open at the opener).
    static func openerViolations(path: String, text: String) -> [String] {
        var found: [String] = []
        /// Records not yet used: the line each is on and the brace depth of its block.
        var records: [(line: Int, depth: Int)] = []
        var depth = 0
        for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let line = code(of: rawLine)
            if line.contains("func ") {
                records = []
                depth = 0
            }
            let characters = Array(line)
            var position = 0
            while position < characters.count {
                let rest = String(characters[position...])
                if characters[position] == "{" {
                    depth += 1
                } else if characters[position] == "}" {
                    depth -= 1
                    // The block that held a record has closed, so the record no longer sits on the path to what follows.
                    records.removeAll { $0.depth > depth }
                } else if rest.hasPrefix("NetworkTrap.record(") {
                    records.append((index, depth))
                } else if let opener = connectionOpeners.first(where: { rest.hasPrefix($0) }),
                    exemptions["\(path)|\(opener)"] == nil
                {
                    if let match = records.lastIndex(where: { index - $0.line <= window }) {
                        records.remove(at: match)
                    } else {
                        found.append(
                            "\(path):\(index + 1): `\(opener)` opens a connection with no NetworkTrap.record "
                                + "in the \(window) lines above it, in the same function, on its path")
                    }
                }
                position += 1
            }
        }
        return found
    }

    /// The code of a line: string contents and a trailing `//` comment removed, so a brace in either does not count.
    private static func code(of line: String) -> String {
        var result = line.replacing(#/"[^"]*"/#, with: "\"\"")
        if let comment = result.firstRange(of: "//") { result = String(result[..<comment.lowerBound]) }
        return result
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
