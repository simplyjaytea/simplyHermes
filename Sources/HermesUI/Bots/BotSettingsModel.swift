#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation
    import SwiftUI

    /// State and network coordination for the full bot configuration screen (WP-42 contract, PR B).
    @MainActor
    @Observable
    public final class BotSettingsModel {
        public let entry: BotRosterEntry
        public var draft: BotSettingsDraft?
        public private(set) var isLoading = false
        public private(set) var isSaving = false
        public var errorMessage: String?
        public var statusMessage: String?
        public var confirmRequired = false
        public var confirmMessage: String?
        public var modelOptions: [ModelOptionProvider] = []
        public var skillSearchText = ""
        public var isExporting = false
        public var shareFile: ShareFile?

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let rosterModel: BotsModel?

        public init(entry: BotRosterEntry, connections: ConnectionsModel) {
            self.entry = entry
            self.connections = connections
            self.rosterModel = nil
        }

        init(entry: BotRosterEntry, connections: ConnectionsModel, rosterModel: BotsModel?) {
            self.entry = entry
            self.connections = connections
            self.rosterModel = rosterModel
        }

        /// Loads `profiles.describe` and `model.options` for the target bot.
        public func load() async {
            guard let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else {
                errorMessage = "The server is offline or unreachable."
                return
            }

            isLoading = true
            errorMessage = nil
            statusMessage = nil
            defer { isLoading = false }

            do {
                let client = try await manager.client(for: connection)
                let botClient = BotClient(gateway: client)

                let describe = try await botClient.describeProfile(entry.profile)
                let options = try? await botClient.modelOptions(profile: entry.profile)

                draft = BotSettingsDraft(
                    describe: describe,
                    title: entry.title,
                    role: entry.role,
                    avatar: entry.avatar,
                    isPinned: entry.isPinned,
                    isHidden: entry.isHidden
                )
                modelOptions = options?.providers ?? []
            } catch {
                errorMessage = BotSettingsError.message(for: error)
            }
        }

        /// Saves dirty sections via `profiles.configure` and metadata namespaces.
        @discardableResult
        public func save() async -> Bool {
            guard var currentDraft = draft, currentDraft.isDirty, currentDraft.isValid else { return false }
            guard let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else {
                errorMessage = "The server is offline or unreachable."
                return false
            }

            isSaving = true
            errorMessage = nil
            statusMessage = nil
            defer { isSaving = false }

            do {
                let client = try await manager.client(for: connection)
                let coordinator = BotSettingsCoordinator(client: BotClient(gateway: client))

                if let outcome = try await coordinator.save(draft: &currentDraft) {
                    draft = currentDraft

                    if outcome.confirmRequired {
                        confirmRequired = true
                        confirmMessage = outcome.confirmMessage
                        return false
                    }

                    statusMessage = outcome.statusMessage

                    if !outcome.isCompleteSuccess {
                        errorMessage = outcome.statusMessage
                        return false
                    }
                } else {
                    draft = currentDraft
                    statusMessage = "All changes saved."
                }

                await rosterModel?.reload()
                return true
            } catch {
                errorMessage = BotSettingsError.message(for: error)
                return false
            }
        }

        /// Re-sends the model change carrying `confirm_expensive_model: true`.
        @discardableResult
        public func confirmExpensiveModelChange() async -> Bool {
            guard var currentDraft = draft else { return false }
            guard currentDraft.buildConfigureParams(confirmExpensiveModel: true) != nil else { return false }
            guard let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else {
                errorMessage = "The server is offline or unreachable."
                return false
            }

            isSaving = true
            errorMessage = nil
            statusMessage = nil
            confirmRequired = false
            confirmMessage = nil
            defer { isSaving = false }

            do {
                let client = try await manager.client(for: connection)
                let coordinator = BotSettingsCoordinator(client: BotClient(gateway: client))
                let outcome = try await coordinator.confirmExpensiveModelChange(draft: &currentDraft)
                draft = currentDraft

                if outcome.isCompleteSuccess {
                    statusMessage = outcome.statusMessage
                    await rosterModel?.reload()
                    return true
                } else {
                    errorMessage = outcome.statusMessage
                    return false
                }
            } catch {
                errorMessage = BotSettingsError.message(for: error)
                return false
            }
        }

        /// Exports the bot profile as an archive file for sharing.
        public func exportBot() async {
            guard let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else {
                errorMessage = "The server is offline or unreachable."
                return
            }

            isExporting = true
            defer { isExporting = false }

            do {
                _ = try await manager.client(for: connection)
                guard let rest = await manager.rest(for: connection.id) else {
                    throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
                }
                let archive = try await rest.exportProfileArchive(name: entry.profile)
                let file = try await Task.detached {
                    try archive.writeTemporaryFile(for: self.entry.profile)
                }.value
                shareFile = ShareFile(url: file)
            } catch {
                errorMessage = ProfileTransferError.describe(error)
            }
        }
    }
#endif
