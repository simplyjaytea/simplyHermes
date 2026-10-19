import Foundation

/// One line of a unified diff, with its line number on each side. A removed line has no new number, and an added
/// line has no old number.
public struct GitDiffLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case context
        case added
        case removed
    }

    public var kind: Kind
    public var oldNumber: Int?
    public var newNumber: Int?
    /// The line without its `+`, `-`, or space marker.
    public var text: String
}

/// One `@@` hunk of a unified diff.
public struct GitDiffHunk: Sendable, Equatable {
    /// The whole `@@ -a,b +c,d @@` header line.
    public var header: String
    public var lines: [GitDiffLine]
}

/// One row of the side-by-side view. A side is nil where the other side has an insertion or a deletion.
public struct GitDiffRow: Sendable, Equatable {
    public var old: GitDiffLine?
    public var new: GitDiffLine?
}

/// Reads the unified diff text that `GET /api/git/review/diff` returns.
public enum GitDiffParser {
    /// Splits `diff` into hunks. File headers and `\ No newline` markers are dropped, and text before the first hunk
    /// is ignored.
    public static func hunks(in diff: String) -> [GitDiffHunk] {
        var hunks: [GitDiffHunk] = []
        var inHunk = false
        var oldNumber = 0
        var newNumber = 0
        for line in lines(of: diff) {
            if line.hasPrefix("@@") {
                (oldNumber, newNumber) = hunkStart(line)
                hunks.append(GitDiffHunk(header: String(line), lines: []))
                inHunk = true
                continue
            }
            guard inHunk else { continue }
            if line.hasPrefix("diff ") {
                inHunk = false
                continue
            }
            if line.first == "\\" { continue }
            var entry = GitDiffLine(kind: .context, oldNumber: nil, newNumber: nil, text: String(line.dropFirst()))
            switch line.first {
            case "+": entry.kind = .added
            case "-": entry.kind = .removed
            default: entry.kind = .context
            }
            switch entry.kind {
            case .context:
                entry.oldNumber = oldNumber
                entry.newNumber = newNumber
                oldNumber += 1
                newNumber += 1
            case .removed:
                entry.oldNumber = oldNumber
                oldNumber += 1
            case .added:
                entry.newNumber = newNumber
                newNumber += 1
            }
            hunks[hunks.count - 1].lines.append(entry)
        }
        return hunks
    }

    /// The side-by-side rows of one hunk. A run of removed lines pairs with the run of added lines that follows it,
    /// so a changed line sits across from its replacement. Context lines appear on both sides.
    public static func rows(in hunk: GitDiffHunk) -> [GitDiffRow] {
        var rows: [GitDiffRow] = []
        var removed: [GitDiffLine] = []
        var added: [GitDiffLine] = []
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                rows.append(
                    GitDiffRow(
                        old: index < removed.count ? removed[index] : nil,
                        new: index < added.count ? added[index] : nil))
            }
            removed.removeAll()
            added.removeAll()
        }
        for line in hunk.lines {
            switch line.kind {
            case .removed:
                removed.append(line)
            case .added:
                added.append(line)
            case .context:
                flush()
                rows.append(GitDiffRow(old: line, new: line))
            }
        }
        flush()
        return rows
    }

    /// The lines of `diff`, without the newline that ends the last one.
    private static func lines(of diff: String) -> [Substring] {
        var text = Substring(diff)
        if text.hasSuffix("\n") { text = text.dropLast() }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// The old and new start lines of a `@@ -a,b +c,d @@` header.
    private static func hunkStart(_ header: Substring) -> (old: Int, new: Int) {
        let parts = header.split(separator: " ")
        func start(_ part: Substring?) -> Int {
            guard let part else { return 0 }
            return Int(part.dropFirst().prefix(while: { $0 != "," })) ?? 0
        }
        return (start(parts.count > 1 ? parts[1] : nil), start(parts.count > 2 ? parts[2] : nil))
    }
}
