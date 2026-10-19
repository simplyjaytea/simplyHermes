import Foundation

/// Copies of server files that the app shows from its temporary folder, such as the file QuickLook opens (WP-37).
///
/// Each copy sits in a folder of its own, so it keeps the server's file name (QuickLook reads the type from it) and
/// removing the copy removes the folder. Nothing deletes a copy by itself: the screen that made it removes it when it
/// closes, and ``removeAll()`` clears what an earlier run left behind.
public struct PreviewCopies: Sendable {
    /// The folder that holds every copy. Nothing else lives there.
    public let directory: URL

    /// Creates copies below `directory`. The default is a folder of the temporary directory.
    public init(directory: URL? = nil) {
        let temporary = FileManager.default.temporaryDirectory
        self.directory = directory ?? temporary.appendingPathComponent("PreviewCopies", isDirectory: true)
    }

    /// Writes `data` as a new copy called `name` and returns its URL. A failed write leaves nothing behind.
    public func write(_ data: Data, named name: String) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return url
    }

    /// Deletes a copy made by ``write(_:named:)`` together with its folder. Any other URL is left alone.
    public func remove(_ copy: URL) {
        let folder = copy.deletingLastPathComponent()
        let parent = folder.deletingLastPathComponent()
        guard parent.standardizedFileURL.path == directory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes every copy, such as the ones an earlier run left behind.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
