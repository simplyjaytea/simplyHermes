#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The state of Bot settings (WP-41): the export and import of the bot the "Applies to" choice points at.
    @MainActor
    @Observable
    public final class BotSettingsModel {
        /// True while an export or an import runs.
        public private(set) var isWorking = false
        /// What went wrong last, as a sentence to show. Nil when nothing did.
        public private(set) var problem: String?
        /// What the last import created, as a sentence to show.
        public private(set) var notice: String?

        @ObservationIgnored private let profiles: ProfilesModel
        @ObservationIgnored private let connections: ConnectionsModel
        /// The folder holding the last export, removed by ``discardExport()``.
        @ObservationIgnored private var exportFolder: URL?

        /// Creates the model for the profiles and servers the app already holds.
        public init(profiles: ProfilesModel, connections: ConnectionsModel) {
            self.profiles = profiles
            self.connections = connections
        }

        /// The bot the "Applies to" choice points at. Export acts on it.
        public var target: String? {
            profiles.appliesTo.target(in: profiles.selection.profiles, active: profiles.selection.current?.name)
        }

        /// Exports the target bot into a new folder in the temporary directory and returns the file for the share sheet.
        /// Nil when the export failed, and ``problem`` says why. The file stays until ``discardExport()``.
        public func exportTarget() async -> URL? {
            guard let name = target, let connection = connections.active, let manager = connections.manager else {
                return nil
            }
            await discardExport()
            isWorking = true
            defer { isWorking = false }
            notice = nil
            do {
                let rest = try await restClient(for: connection, manager: manager)
                let archive = try await rest.exportProfileArchive(name: name)
                let file = try await Task.detached { try archive.writeTemporaryFile(for: name) }.value
                exportFolder = file.deletingLastPathComponent()
                problem = nil
                return file
            } catch {
                problem = ProfileTransferError.describe(error)
                return nil
            }
        }

        /// Removes the file of the last export. The sheet calls it when the share sheet closes, and the next export calls
        /// it first, so an archive of a bot never outlives its share.
        public func discardExport() async {
            guard let folder = exportFolder else { return }
            exportFolder = nil
            await Task.detached {
                _ = try? FileManager.default.removeItem(at: folder)
            }.value
        }

        /// Creates a bot from an archive the user picked, then refreshes the switcher. The file is read off the main actor.
        public func importArchive(from url: URL) async {
            guard let connection = connections.active, let manager = connections.manager else { return }
            isWorking = true
            defer { isWorking = false }
            problem = nil
            notice = nil
            let archive: Data
            do {
                archive = try await Self.readArchive(at: url)
            } catch {
                problem = "The file could not be read."
                return
            }
            do {
                let rest = try await restClient(for: connection, manager: manager)
                let result = try await rest.importProfileArchive(archive)
                notice = result.name.map { "Created \($0)." } ?? "Created the bot from the archive."
            } catch {
                problem = ProfileTransferError.describe(error)
                return
            }
            await profiles.refresh()
        }

        /// Reads the picked file on a background task, inside the file's security scope.
        private static func readArchive(at url: URL) async throws -> Data {
            try await Task.detached {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }.value
        }

        /// Connects on demand and returns the signed-in REST client of the connection.
        private func restClient(
            for connection: ServerConnection, manager: ConnectionManager
        ) async throws -> RESTClient {
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
            }
            return rest
        }
    }
#endif
