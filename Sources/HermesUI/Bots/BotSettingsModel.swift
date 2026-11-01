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

        public init(entry: BotRosterEntry, connections: ConnectionsModel, rosterModel: BotsModel? = nil) {
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

                async let describeCall = botClient.describeProfile(entry.profile)
                async let optionsCall = botClient.modelOptions(profile: entry.profile)

                let (describe, options) = try await (describeCall, optionsCall)

                draft = BotSettingsDraft(
                    describe: describe,
                    title: entry.title,
                    role: entry.role,
                    avatar: entry.avatar,
                    isPinned: entry.isPinned,
                    isHidden: entry.isHidden
                )
                modelOptions = options.providers
            } catch {
                errorMessage = BotSettingsError.message(for: error)
            }
        }

        /// Saves dirty sections via `profiles.configure` and metadata namespaces.
        @discardableResult
        public func save() async -> Bool {
            guard let currentDraft = draft, currentDraft.isDirty, currentDraft.isValid else { return false }
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
                let botClient = BotClient(gateway: client)

                // 1. Identity metadata writes (Desktop and App namespaces)
                var identityApplied = true
                if currentDraft.isIdentityDirty {
                    if currentDraft.title != entry.title || currentDraft.isPinned != entry.isPinned
                        || currentDraft.isHidden != entry.isHidden
                    {
                        try await botClient.updateNamespace(
                            profile: entry.profile, namespace: BotMetaNamespace.desktop
                        ) { meta in
                            if currentDraft.title != entry.title {
                                meta.title = currentDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            meta.pinned = currentDraft.isPinned
                            meta.hidden = currentDraft.isHidden
                        }
                    }
                    if currentDraft.avatar != entry.avatar {
                        try await botClient.updateNamespace(
                            profile: entry.profile, namespace: BotMetaNamespace.app
                        ) { object in
                            object = BotAppLook(avatar: currentDraft.avatar).applied(to: object)
                        }
                    }
                }

                // 2. Configure dirty sections
                if let params = currentDraft.buildConfigureParams() {
                    let result = try await botClient.configureProfile(params)
                    let outcome = BotSettingsSaveOutcome.evaluate(
                        result: result,
                        requestedSections: currentDraft.dirtySections,
                        hasRoleDirty: currentDraft.isRoleDirty
                    )

                    if outcome.confirmRequired {
                        confirmRequired = true
                        confirmMessage = outcome.confirmMessage
                        return false
                    }

                    draft?.applySuccessfulSections(outcome.appliedSections)
                    statusMessage = outcome.statusMessage

                    if !outcome.isCompleteSuccess {
                        errorMessage = outcome.statusMessage
                        return false
                    }
                } else if identityApplied {
                    draft?.applySuccessfulSections([.identity])
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
        public func confirmExpensiveModelChange() async {
            guard let currentDraft = draft else { return }
            guard let params = currentDraft.buildConfigureParams(confirmExpensiveModel: true) else { return }
            guard let connection = connections.connection(id: entry.connectionID),
                let manager = connections.manager
            else {
                errorMessage = "The server is offline or unreachable."
                return
            }

            isSaving = true
            errorMessage = nil
            statusMessage = nil
            confirmRequired = false
            confirmMessage = nil
            defer { isSaving = false }

            do {
                let client = try await manager.client(for: connection)
                let result = try await BotClient(gateway: client).configureProfile(params)
                let outcome = BotSettingsSaveOutcome.evaluate(
                    result: result,
                    requestedSections: [.model]
                )

                if outcome.isCompleteSuccess {
                    draft?.applySuccessfulSections([.model])
                    statusMessage = "Model updated successfully."
                    await rosterModel?.reload()
                } else {
                    errorMessage = outcome.statusMessage
                }
            } catch {
                errorMessage = BotSettingsError.message(for: error)
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
