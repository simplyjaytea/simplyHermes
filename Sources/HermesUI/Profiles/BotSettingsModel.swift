#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The state of Bot settings (WP-41): the bots of the active server, the one the "Applies to" choice points at, and
    /// the export and import of a bot's profile.
    @MainActor
    @Observable
    public final class BotSettingsModel {
        /// The bots of the active server, read from `profiles.list`. Empty until the first load.
        public private(set) var roster: [BotFacts] = []
        /// True while a load, an export or an import runs.
        public private(set) var isWorking = false
        /// What went wrong last, as a sentence to show. Nil when nothing did.
        public private(set) var problem: String?
        /// What the last import created, as a sentence to show.
        public private(set) var notice: String?

        @ObservationIgnored private let profiles: ProfilesModel
        @ObservationIgnored private let connections: ConnectionsModel

        /// Creates the model for the profiles and servers the app already holds.
        public init(profiles: ProfilesModel, connections: ConnectionsModel) {
            self.profiles = profiles
            self.connections = connections
        }

        /// The bot the "Applies to" choice points at. Export acts on it.
        public var target: String? {
            profiles.appliesTo.target(in: profiles.selection.profiles, active: profiles.selection.current?.name)
        }

        /// The facts of the target bot, once the roster has loaded.
        public var facts: BotFacts? {
            guard let target else { return nil }
            return roster.first { $0.name == target }
        }

        /// Reads the roster of the active server, connecting on demand.
        public func load() async {
            guard let connection = connections.active, let manager = connections.manager else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                let client = try await manager.client(for: connection)
                let result: ProfilesListResult = try await client.call(
                    "profiles.list", params: ProfilesListParams(includeSessions: true))
                roster = result.profiles.map(BotFacts.init(row:))
                problem = nil
            } catch {
                problem = ProfileTransferError.describe(error)
            }
        }

        /// Exports the target bot to a file in the temporary directory and returns it for the share sheet. Nil when the
        /// export failed, and ``problem`` says why.
        public func exportTarget() async -> URL? {
            guard let name = target, let connection = connections.active, let manager = connections.manager else {
                return nil
            }
            isWorking = true
            defer { isWorking = false }
            do {
                let rest = try await restClient(for: connection, manager: manager)
                let archive = try await rest.exportProfileArchive(name: name)
                let file = try archive.writeTemporaryFile(for: name)
                problem = nil
                notice = nil
                return file
            } catch {
                problem = ProfileTransferError.describe(error)
                return nil
            }
        }

        /// Creates a bot from an archive the user picked, then refreshes the switcher and the roster.
        public func importArchive(from url: URL) async {
            guard let connection = connections.active, let manager = connections.manager else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let archive = try? Data(contentsOf: url) else {
                problem = "The file could not be read."
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                let rest = try await restClient(for: connection, manager: manager)
                let result = try await rest.importProfileArchive(archive)
                problem = nil
                notice = result.name.map { "Created \($0)." } ?? "Created the bot from the archive."
            } catch {
                problem = ProfileTransferError.describe(error)
                return
            }
            await profiles.refresh()
            await load()
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
