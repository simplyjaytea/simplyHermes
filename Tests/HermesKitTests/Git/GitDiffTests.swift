import HermesKit
import Testing

@Suite struct GitDiffParserTests {
    private let sample = [
        "diff --git a/App.swift b/App.swift",
        "index 1111111..2222222 100644",
        "--- a/App.swift",
        "+++ b/App.swift",
        "@@ -10,4 +10,5 @@ struct App {",
        " let name = \"hermes\"",
        "-let port = 8000",
        "+let port = 8642",
        "+let host = \"127.0.0.1\"",
        " print(name)",
        "-exit(1)",
        "\\ No newline at end of file",
    ].joined(separator: "\n")

    @Test func parsesOneHunkWithLineNumbersOnEachSide() throws {
        let hunks = GitDiffParser.hunks(in: sample)
        let hunk = try #require(hunks.first)
        #expect(hunks.count == 1)
        #expect(hunk.header == "@@ -10,4 +10,5 @@ struct App {")
        #expect(hunk.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .removed])
        #expect(hunk.lines[0].oldNumber == 10 && hunk.lines[0].newNumber == 10)
        #expect(hunk.lines[1].oldNumber == 11 && hunk.lines[1].newNumber == nil)
        #expect(hunk.lines[2].oldNumber == nil && hunk.lines[2].newNumber == 11)
        #expect(hunk.lines[2].text == "let port = 8642")
        #expect(hunk.lines[3].newNumber == 12)
        #expect(hunk.lines[4].oldNumber == 12 && hunk.lines[4].newNumber == 13)
        #expect(hunk.lines[5].oldNumber == 13 && hunk.lines[5].newNumber == nil)
    }

    @Test func emptyDiffHasNoHunks() {
        #expect(GitDiffParser.hunks(in: "").isEmpty)
    }

    @Test func trailingNewlineAddsNoLine() throws {
        let hunk = try #require(GitDiffParser.hunks(in: sample + "\n").first)
        #expect(hunk.lines.count == 6)
    }

    @Test func eachHunkNumbersFromItsOwnHeader() throws {
        let diff = [
            "@@ -1,2 +1,2 @@",
            " a",
            "-b",
            "+c",
            "@@ -40,1 +41,2 @@",
            "-x",
            "+y",
            "+z",
        ].joined(separator: "\n")
        let hunks = GitDiffParser.hunks(in: diff)
        #expect(hunks.count == 2)
        #expect(hunks[1].lines.first?.oldNumber == 40)
        #expect(hunks[1].lines.last?.newNumber == 42)
    }

    @Test func pairsChangedLinesAcrossTheSideBySideRows() throws {
        let hunk = try #require(GitDiffParser.hunks(in: sample).first)
        let rows = GitDiffParser.rows(in: hunk)
        #expect(rows.count == 5)
        #expect(rows[0].old?.text == "let name = \"hermes\"" && rows[0].new?.text == "let name = \"hermes\"")
        #expect(rows[1].old?.text == "let port = 8000" && rows[1].new?.text == "let port = 8642")
        #expect(rows[2].old == nil && rows[2].new?.text == "let host = \"127.0.0.1\"")
        #expect(rows[3].old?.text == "print(name)" && rows[3].new?.text == "print(name)")
        #expect(rows[4].old?.text == "exit(1)" && rows[4].new == nil)
    }
}
