import Foundation
import Testing

/// The rules that keep every network connection counted (WP-7, AT-2b). Both checks take a path relative to `Sources/` and
/// the file's text, so the real tree and the test fixtures go through the same code. Both read code only: comments are
/// gone, strings are blanked, and the code inside a string's `\( )` interpolation is read (``SwiftSourceScanner``).
///
/// 1. Sessions: a `URLSession` may be created only in the factory file. `URLSession(`, `URLSession.init(`,
///    `URLSession.shared`, the type taken as a value (`URLSession.self`, `.Type`), a `typealias` of it, an
///    `extension URLSession`, a subclass, a generic constrained to it and `type(of:).init` are all refused elsewhere.
///    Every other session must come from `NetworkSessions.make`, which puts the counting protocol first.
/// 2. Other openers (`ClientBootstrap`, `NIOTSConnectionBootstrap`, `NWConnection`, `ServerBootstrap`, `SSHClient.connect`):
///    each call, `.init` or method reference needs its own `NetworkTrap.record(` on one of the `window` lines above it,
///    in the same function, and the record must be on the opener's path: in the same block or one that encloses it. A
///    record in a branch that has closed does not count. A record covers only the next opener after it. The type taken
///    as a value (`ClientBootstrap.self`) or aliased is refused outright, because it can open a connection anywhere.
///
/// What it cannot see: a type reached only by a generic parameter or by name at run time. Those need a code review.
enum ConnectionGuard {
    /// The only file that may create a `URLSession`.
    static let factoryPath = "HermesKit/Diagnostics/NetworkSessions.swift"

    /// Types that open an outgoing connection when they are created, with the name the exemptions use (`Name(`).
    static let connectionTypes = ["ClientBootstrap", "NIOTSConnectionBootstrap", "NWConnection", "ServerBootstrap"]

    /// Lines above an opener that may hold its `NetworkTrap.record(`.
    static let window = 5

    /// Openers that open no outgoing connection, each with its reason. Keys are `path|opener`.
    static let exemptions: [String: String] = [
        "HermesSSH/LoopbackForwarder.swift|ServerBootstrap(":
            "Listens on loopback for the app's own SSH forwarding. It accepts no outgoing connection; the outgoing SSH "
            + "connection is counted at SSHClient.connect."
    ]

    // MARK: Rule 1

    /// Rule 1: session creation outside the factory, directly, through the type as a value, an alias or an extension.
    /// Read on code only (comments gone, strings blanked, interpolation kept), and tolerant of white space, line breaks
    /// and a module prefix: `Foundation.URLSession (` is a session as much as `URLSession(`.
    static func sessionViolations(path: String, text: String) -> [String] {
        guard path != factoryPath else { return [] }
        let code = GuardedCode(text)
        let rules: [(pattern: String, message: String)] = [
            (#"\bURLSession\s*(?:\.\s*init\b|\()"#, "creates a URLSession outside NetworkSessions.make"),
            (#"\bURLSession\s*\.\s*shared\b"#, "uses URLSession.shared outside NetworkSessions.make"),
            (
                #"\bURLSession\s*\.\s*(?:self|Type)\b"#,
                "takes the URLSession type as a value, which can create one, outside NetworkSessions.make"
            ),
            (
                #"typealias\s+\w+\s*=\s*(?:\w+\.)*URLSession(?:[^.\w]|$)"#,
                "aliases URLSession outside NetworkSessions.make"
            ),
            (#"extension\s+(?:\w+\.)*URLSession(?:[^.\w]|$)"#, "extends URLSession outside NetworkSessions.make"),
            // A subclass, or a generic that is constrained to the type, can create sessions under another name.
            (
                #"\bclass\s+\w+(?:<[^>]*>)?\s*:\s*[^{]*\bURLSession\b"#,
                "subclasses URLSession outside NetworkSessions.make"
            ),
            (
                #"<[^>\n]*:\s*(?:\w+\.)*URLSession\b[^>\n]*>"#,
                "constrains a generic to URLSession outside NetworkSessions.make"
            ),
            (
                #"\bwhere\s+[^{\n]*:\s*(?:\w+\.)*URLSession\b"#,
                "constrains a generic to URLSession outside NetworkSessions.make"
            ),
            (
                #"\btype\s*\(\s*of\s*:[^)]*\)\s*\.\s*init\b"#,
                "calls init on the type of a value outside NetworkSessions.make"
            ),
        ]
        var found: [(line: Int, message: String)] = []
        for rule in rules {
            for hit in code.find(rule.pattern) { found.append((hit.line, rule.message)) }
        }
        return found.sorted { $0.line < $1.line }.map { "\(path):\($0.line + 1): \($0.message)" }
    }

    // MARK: Rule 2

    /// Every site in the file, by line.
    private static func sites(in code: GuardedCode) -> [Int: [ConnectionSite]] {
        var found: [Int: [ConnectionSite]] = [:]
        func add(_ pattern: String, _ kind: ConnectionSiteKind) {
            for hit in code.find(pattern) {
                found[hit.line, default: []].append(ConnectionSite(column: hit.column, kind: kind))
            }
        }
        for name in connectionTypes {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            add(#"\b\#(escaped)\s*(?:\.\s*init\b|\()"#, .opens("\(name)("))
            add(#"\b\#(escaped)\s*\.\s*(?:self|Type)\b"#, .escapes("`\(name)` taken as a value"))
            add(#"typealias\s+\w+\s*=\s*(?:\w+\.)*\#(escaped)\b"#, .escapes("`\(name)` aliased"))
        }
        // SSH: the connect call, or a reference to it that is called later.
        add(#"\bSSHClient\s*\.\s*connect\b"#, .opens("SSHClient.connect("))
        add(#"\bSSHClient\s*\.\s*(?:self|Type)\b"#, .escapes("`SSHClient` taken as a value"))
        add(#"typealias\s+\w+\s*=\s*(?:\w+\.)*SSHClient\b"#, .escapes("`SSHClient` aliased"))
        return found
    }

    /// Rule 2: each connection opener is recorded by its own record in the window above it, in the same function, on its
    /// path (the record's block is still open at the opener). The type taken as a value, or aliased, is refused outright.
    static func openerViolations(path: String, text: String) -> [String] {
        let code = GuardedCode(text)
        let sitesByLine = sites(in: code)
        var recordsByLine: [Int: [Int]] = [:]
        for hit in code.find(#"\bNetworkTrap\s*\.\s*record\s*\("#) {
            recordsByLine[hit.line, default: []].append(hit.column)
        }
        var walk = RecordWalk(path: path, window: window, exemptions: exemptions)
        for (index, line) in code.lines.enumerated() {
            if line.contains("func ") { walk.startFunction() }
            var events = braceEvents(in: line)
            events += (recordsByLine[index] ?? []).map { LineEvent(column: $0, order: 1, action: .record) }
            events += (sitesByLine[index] ?? []).map { LineEvent(column: $0.column, order: 2, action: .site($0)) }
            for event in events.sorted(by: { ($0.column, $0.order) < ($1.column, $1.order) }) {
                walk.apply(event.action, line: index)
            }
        }
        return walk.found
    }

    private static func braceEvents(in line: String) -> [LineEvent] {
        Array(line).enumerated().compactMap { column, character in
            switch character {
            case "{": LineEvent(column: column, order: 0, action: .openBrace)
            case "}": LineEvent(column: column, order: 0, action: .closeBrace)
            default: nil
            }
        }
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

/// The code of a file, ready to be searched. A match may span lines: `URLSession` on one line and `.shared` or `(` on the
/// next is the same call, so patterns run over the whole file and a hit is reported at the line it starts on.
private struct GuardedCode {
    let lines: [String]
    private let joined: String
    private let starts: [Int]

    init(_ text: String) {
        lines = SwiftSourceScanner.codeLines(text, keepStrings: false)
        joined = lines.joined(separator: "\n")
        var offsets: [Int] = []
        var next = 0
        for line in lines {
            offsets.append(next)
            next += line.count + 1
        }
        starts = offsets
    }

    /// Where `pattern` matches, as (line, column), both from zero. Word boundaries are the simple kind: Swift's default
    /// `\b` follows the Unicode word rules, under which `shared.data` is one word and `URLSession.shared` would have no
    /// boundary after `shared`.
    func find(_ pattern: String) -> [(line: Int, column: Int)] {
        // The patterns are fixed in this file, so a bad one is a bug here and fails every test.
        guard let regex = try? Regex(pattern).wordBoundaryKind(.simple) else {
            preconditionFailure("Bad guard pattern: \(pattern)")
        }
        return joined.matches(of: regex).map { match in
            let offset = joined.distance(from: joined.startIndex, to: match.range.lowerBound)
            let line = starts.lastIndex(where: { $0 <= offset }) ?? 0
            return (line, offset - starts[line])
        }
    }
}

private enum ConnectionSiteKind {
    /// A call, `.init` or a method reference: needs its own record. The text is the exemption key.
    case opens(String)
    /// The type taken as a value, or aliased: it can open a connection anywhere, so no record can cover it.
    case escapes(String)
}

/// One place that creates, or can create, a connection.
private struct ConnectionSite {
    var column: Int
    var kind: ConnectionSiteKind
}

private enum LineAction {
    case openBrace
    case closeBrace
    case record
    case site(ConnectionSite)
}

private struct LineEvent {
    var column: Int
    /// Braces first, then records, then sites, when they share a column.
    var order: Int
    var action: LineAction
}

/// The state of rule 2 while it walks a file: the brace depth, the records not yet used, and what it found.
private struct RecordWalk {
    let path: String
    let window: Int
    let exemptions: [String: String]
    var found: [String] = []
    /// Records not yet used: the line each is on and the brace depth of its block.
    private var records: [(line: Int, depth: Int)] = []
    private var depth = 0

    init(path: String, window: Int, exemptions: [String: String]) {
        self.path = path
        self.window = window
        self.exemptions = exemptions
    }

    mutating func startFunction() {
        records = []
        depth = 0
    }

    mutating func apply(_ action: LineAction, line: Int) {
        switch action {
        case .openBrace:
            depth += 1
        case .closeBrace:
            depth -= 1
            // The block that held a record has closed, so the record no longer sits on the path.
            records.removeAll { $0.depth > depth }
        case .record:
            records.append((line, depth))
        case .site(let site):
            visit(site, line: line)
        }
    }

    private mutating func visit(_ site: ConnectionSite, line: Int) {
        switch site.kind {
        case .escapes(let what):
            found.append("\(path):\(line + 1): \(what): it can open a connection that no NetworkTrap.record covers")
        case .opens(let opener):
            guard exemptions["\(path)|\(opener)"] == nil else { return }
            if let match = records.lastIndex(where: { line - $0.line <= window }) {
                records.remove(at: match)
            } else {
                found.append(
                    "\(path):\(line + 1): `\(opener)` opens a connection with no NetworkTrap.record "
                        + "in the \(window) lines above it, in the same function, on its path")
            }
        }
    }
}
