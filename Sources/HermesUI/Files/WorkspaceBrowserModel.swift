#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// Browses the active server's folders and reads its text files, read-only (WP-37).
    ///
    /// It needs a signed-in connection. Until one is up it says so, and the next `load()` tries again.
    @MainActor
    @Observable
    public final class WorkspaceBrowserModel {
        /// The folders a chat can run in. Nil until the first load succeeds.
        public private(set) var workspaces: WorkspaceList?
        /// The folder on screen, an absolute path on the server.
        public private(set) var folder: String?
        public private(set) var entries: [FsEntry] = []
        /// Why nothing new shows, such as an unreadable folder or no connection.
        public private(set) var notice: String?
        /// The text file opened from the list, until its sheet closes.
        public private(set) var preview: FsText?
        /// A binary file copied to the temporary folder, shown in QuickLook until it closes (WP-37).
        public private(set) var quickLookURL: URL?
        @ObservationIgnored private let connections: ConnectionsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Loads the workspace list and opens its default folder. Does nothing once the list is in.
        public func load() async {
            guard workspaces == nil, let rest = await restClient() else { return }
            do {
                let list = try await rest.workspaces()
                workspaces = list
                await show(list.defaultCwd, using: rest)
            } catch {
                notice = "Could not load the workspaces."
            }
        }

        /// Opens a folder in place, or reads a text file into the preview.
        public func select(_ entry: FsEntry) async {
            guard let rest = await restClient() else { return }
            if entry.isDirectory {
                await show(entry.path, using: rest)
            } else {
                await read(entry.path, using: rest)
            }
        }

        /// Goes to the folder above the one on screen.
        public func up() async {
            guard let folder, let rest = await restClient() else { return }
            await show(URL(fileURLWithPath: folder).deletingLastPathComponent().path, using: rest)
        }

        /// Closes the preview.
        public func closePreview() {
            preview = nil
        }

        /// Closes the QuickLook preview.
        public func closeQuickLook() {
            quickLookURL = nil
        }

        /// The bytes of an image the server named, by path or URL. Nil when there is no connection or the fetch fails.
        public func mediaData(_ image: String) async -> Data? {
            guard let rest = await restClient() else { return nil }
            if image.hasPrefix("http://") || image.hasPrefix("https://") {
                return try? await rest.proxiedMedia(url: image)
            }
            return try? await rest.mediaFile(path: image)
        }

        private func restClient() async -> RESTClient? {
            guard let connection = connections.active, let manager = connections.manager,
                let rest = await manager.rest(for: connection.id)
            else {
                notice = "Connect to a server to browse its files."
                return nil
            }
            return rest
        }

        private func show(_ path: String, using rest: RESTClient) async {
            folder = path
            do {
                let list = try await rest.listFolder(path)
                entries = list.entries.sorted(by: Self.foldersFirst)
                notice = list.error.map { "Could not read this folder (\($0))." }
            } catch {
                entries = []
                notice = "Could not read this folder."
            }
        }

        private func read(_ path: String, using rest: RESTClient) async {
            do {
                let file = try await rest.readText(path)
                if file.binary {
                    quickLookURL = try await Self.localCopy(of: path, using: rest)
                } else {
                    preview = file
                }
            } catch {
                notice = "Could not open this file."
            }
        }

        /// Copies a server file into the temporary folder under its own name, so QuickLook can tell its type.
        private static func localCopy(of path: String, using rest: RESTClient) async throws -> URL {
            let data = try await rest.downloadFile(path)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            try data.write(to: url)
            return url
        }

        private static func foldersFirst(_ lhs: FsEntry, _ rhs: FsEntry) -> Bool {
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
#endif
