import Foundation
import HermesKit
import Testing

@Suite struct PreviewCopiesTests {
    /// A folder of its own for one test, so tests never see each other's copies.
    private func makeCopies() -> (copies: PreviewCopies, base: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (PreviewCopies(directory: base.appendingPathComponent("copies", isDirectory: true)), base)
    }

    @Test func writesACopyInAFolderOfItsOwnUnderTheServerName() throws {
        let (copies, base) = makeCopies()
        defer { try? FileManager.default.removeItem(at: base) }

        let url = try copies.write(Data("abc".utf8), named: "report.pdf")

        #expect(url.lastPathComponent == "report.pdf")
        #expect(try Data(contentsOf: url) == Data("abc".utf8))
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().path == copies.directory.path)
    }

    @Test func removingACopyRemovesItsFolderAndNothingElse() throws {
        let (copies, base) = makeCopies()
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try copies.write(Data("1".utf8), named: "a.png")
        let second = try copies.write(Data("2".utf8), named: "a.png")

        copies.remove(first)

        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func aFileOutsideTheDirectoryIsNotRemoved() throws {
        let (copies, base) = makeCopies()
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("keep", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let file = outside.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)

        copies.remove(file)

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removeAllClearsEveryCopy() throws {
        let (copies, base) = makeCopies()
        defer { try? FileManager.default.removeItem(at: base) }
        let url = try copies.write(Data("1".utf8), named: "a.png")

        copies.removeAll()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: copies.directory.path))
    }

    @Test func aFailedWriteLeavesNoFolderBehind() throws {
        let (copies, base) = makeCopies()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(throws: (any Error).self) {
            try copies.write(Data("1".utf8), named: "missing/dir/a.png")
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: copies.directory.path).isEmpty)
    }
}
