#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// Browses the active server's folders and reads its text files, read-only (WP-37).
    ///
    /// It needs a signed-in connection. Until one is up it says so, and the next `load()` tries again. What it shows
    /// belongs to one server: when the active server changes, `load()` drops it and starts over.
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
        @ObservationIgnored private let connections: ConnectionsModel
        /// The server that `workspaces`, `folder` and `entries` came from.
        @ObservationIgnored private var serverID: UUID?
        /// Counts requests and server changes, so an answer that comes in late is dropped.
        @ObservationIgnored private var requestID = 0

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Changes when the active server or its connection does. The view loads again then (`.task(id:)`).
        public var loadKey: String {
            guard let id = connections.active?.id else { return "none" }
            var isConnected = false
            if case .connected = connections.phase(of: id) { isConnected = true }
            return "\(id.uuidString)-\(isConnected)"
        }

        /// Loads the workspace list and opens its default folder. Does nothing once a folder is open for this server.
        public func load() async {
            followActiveServer()
            guard workspaces == nil || folder == nil, let rest = await restClient() else { return }
            requestID += 1
            let request = requestID
            do {
                let list = try await rest.workspaces()
                guard request == requestID else { return }
                workspaces = list
                await show(list.defaultCwd, using: rest)
            } catch {
                guard request == requestID else { return }
                notice = String(localized: "Could not load the workspaces.")
            }
        }

        /// Reads the workspace list again, so folders that came or went on the server show in the picker (WP-37).
        /// Returns why it failed, or nil. It leaves the folder and notice of the file browser alone.
        public func refreshWorkspaces() async -> String? {
            followActiveServer()
            guard let rest = await activeRESTClient() else {
                return String(localized: "Connect to a server to pick a folder.")
            }
            do {
                let list = try await rest.workspaces()
                if isShowingActiveServer { workspaces = list }
                return nil
            } catch {
                return String(localized: "Could not load the folders.")
            }
        }

        /// Opens a folder in place, or reads a text file into the preview.
        public func select(_ entry: FsEntry) async {
            guard isShowingActiveServer, let rest = await restClient() else { return }
            if entry.isDirectory {
                await show(entry.path, using: rest)
            } else {
                await read(entry.path, using: rest)
            }
        }

        /// Goes to the folder above the one on screen.
        public func up() async {
            guard isShowingActiveServer, let folder, let rest = await restClient() else { return }
            await show(URL(fileURLWithPath: folder).deletingLastPathComponent().path, using: rest)
        }

        /// Closes the preview.
        public func closePreview() {
            preview = nil
        }

        private func restClient() async -> RESTClient? {
            guard let rest = await activeRESTClient() else {
                notice = String(localized: "Connect to a server to browse its files.")
                return nil
            }
            return rest
        }

        private func activeRESTClient() async -> RESTClient? {
            guard let connection = connections.active, let manager = connections.manager else { return nil }
            return await manager.rest(for: connection.id)
        }

        /// True while the folders on screen came from the active server.
        private var isShowingActiveServer: Bool { serverID == connections.active?.id }

        /// Drops everything on screen when the active server is not the one it came from, so a folder of one server is
        /// never asked of another. Answers still on their way from the old server are dropped too.
        private func followActiveServer() {
            guard !isShowingActiveServer else { return }
            serverID = connections.active?.id
            requestID += 1
            workspaces = nil
            folder = nil
            entries = []
            notice = nil
            preview = nil
        }

        /// The header names the folder only once its list is in, so the two never disagree.
        private func show(_ path: String, using rest: RESTClient) async {
            requestID += 1
            let request = requestID
            do {
                let list = try await rest.listFolder(path)
                guard request == requestID else { return }
                folder = path
                entries = list.entries.sorted(by: Self.foldersFirst)
                notice = list.error.map { String(localized: "Could not read this folder (\($0)).") }
            } catch {
                guard request == requestID else { return }
                folder = path
                entries = []
                notice = String(localized: "Could not read this folder.")
            }
        }

        private func read(_ path: String, using rest: RESTClient) async {
            let request = requestID
            do {
                let file = try await rest.readText(path)
                guard request == requestID else { return }
                preview = file
            } catch {
                guard request == requestID else { return }
                notice = String(localized: "Could not open this file.")
            }
        }

        private static func foldersFirst(_ lhs: FsEntry, _ rhs: FsEntry) -> Bool {
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
#endif
