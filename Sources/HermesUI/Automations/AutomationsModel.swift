#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The cron jobs of the active server (WP-50). Loads every profile's jobs, reloads them when the server reports
    /// `cron.changed`, and runs the actions. The Bots routines pane (WP-44) reads the same list through this model.
    @MainActor
    @Observable
    public final class AutomationsModel {
        /// Every job of the active server, in the order the server sent them.
        public private(set) var jobs: [CronJob] = []
        /// True while a load runs.
        public private(set) var isLoading = false
        /// True once a list has come back for the active server.
        public private(set) var hasLoaded = false
        /// Set when the last load failed. The last list stays on screen.
        public private(set) var loadError: String?
        /// Set when the last action failed. The next action that works clears it.
        public private(set) var actionError: String?
        /// The chip that narrows the list.
        public var filter: CronJobFilter = .all

        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private var attachedID: UUID?
        @ObservationIgnored private var listener: Task<Void, Never>?
        /// The server's time zone by profile, for the editor's preview. Cleared when the server changes.
        @ObservationIgnored private var zones: [String: String] = [:]

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// The sections the list shows for the current filter.
        public var sections: [CronJobSection] { CronJobGrouping.sections(jobs, filter: filter) }

        /// The bots that have jobs, in list order. The editor offers them.
        public var botNames: [String] { CronJobGrouping.botNames(jobs) }

        /// Called when the Automations tab appears and when the active server changes. For a new server it clears the
        /// old list, starts listening for `cron.changed`, and loads the list.
        public func attach() async {
            guard let connection = connections.active else { return }
            if attachedID != connection.id {
                attachedID = connection.id
                listener?.cancel()
                jobs = []
                hasLoaded = false
                loadError = nil
                actionError = nil
                zones = [:]
                listener = Task { [weak self] in
                    guard let self else { return }
                    await self.listen(to: connection)
                }
            }
            await refresh()
        }

        /// Called when the Automations tab goes away. Stops the `cron.changed` listener; `attach()` starts it again.
        public func detach() {
            listener?.cancel()
            listener = nil
            attachedID = nil
        }

        /// Reloads the list. A failed reload keeps the last list on screen. Only reads: nothing on the server changes.
        public func refresh() async {
            guard connections.active != nil else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                jobs = try await rest().cronJobs()
                hasLoaded = true
                loadError = nil
            } catch is CancellationError {
                return
            } catch {
                loadError = Self.loadMessage(for: error)
            }
        }

        /// The job as the server has it now. The single read is not labelled with its profile, so the profile comes
        /// from the list row.
        public func job(id: String) async throws -> CronJob {
            var job = try await rest().cronJob(id: id)
            if let row = jobs.first(where: { $0.id == id }) {
                job.profile = job.profile ?? row.profile
                job.isDefaultProfile = job.isDefaultProfile ?? row.isDefaultProfile
            }
            return job
        }

        /// The past runs of a job, newest first, as the server lists them.
        public func runs(of id: String) async throws -> [CronRun] {
            try await rest().cronJobRuns(id: id)
        }

        /// The server's time zone for a profile, for the editor's preview: an IANA name, or `""` for the server's own
        /// local time. Nil when it cannot be read.
        public func timeZoneName(forProfile profile: String) async -> String? {
            if let known = zones[profile] { return known }
            guard let name = try? await rest().serverTimeZone(profile: profile) else { return nil }
            zones[profile] = name
            return name
        }

        /// Runs a job now, outside its schedule. Returns whether the server accepted it.
        @discardableResult
        public func runNow(_ job: CronJob) async -> Bool {
            await act { client in try await client.triggerCronJob(id: job.id) }
        }

        /// Pauses a job, or resumes it. Returns whether the server accepted the change.
        @discardableResult
        public func setEnabled(_ job: CronJob, _ enabled: Bool) async -> Bool {
            await act { client in
                if enabled {
                    try await client.resumeCronJob(id: job.id)
                } else {
                    try await client.pauseCronJob(id: job.id)
                }
            }
        }

        /// Deletes a job on the server. The caller asks first. Returns whether the server deleted it.
        @discardableResult
        public func delete(_ job: CronJob) async -> Bool {
            await act { client in try await client.deleteCronJob(id: job.id) }
        }

        /// Creates a job in its profile, or saves the changes to one. Throws when the server refuses, so the editor
        /// can say why.
        public func save(_ change: CronJobSave) async throws {
            let client = try await rest()
            do {
                switch change {
                case .create(let body, let profile):
                    try await client.createCronJob(body, profile: profile)
                case .edit(let id, let changes, let enabledChange):
                    try await client.updateCronJob(id: id, changes)
                    if let enabledChange {
                        if enabledChange {
                            try await client.resumeCronJob(id: id)
                        } else {
                            try await client.pauseCronJob(id: id)
                        }
                    }
                }
            } catch {
                await refresh()
                throw error
            }
            actionError = nil
            await refresh()
        }

        /// Reloads the list on every `cron.changed` from the server's socket, until the task is cancelled.
        private func listen(to connection: ServerConnection) async {
            guard let manager = connections.manager, let client = try? await manager.client(for: connection) else {
                return
            }
            let events = await client.events()
            for await event in events where CronChangeSignal.isChange(event) {
                await refresh()
            }
        }

        /// Runs one change and reloads the list. Returns whether it worked.
        private func act(_ change: (RESTClient) async throws -> Void) async -> Bool {
            do {
                try await change(try await rest())
                actionError = nil
            } catch is CancellationError {
                return false
            } catch {
                actionError = Self.failureText(error, fallback: "That change did not work. Try again.")
                await refresh()
                return false
            }
            await refresh()
            return true
        }

        /// Connects on demand and returns the signed-in REST client of the active server.
        private func rest() async throws -> RESTClient {
            guard let connection = connections.active, let manager = connections.manager else {
                throw ConnectionUnavailable(phase: .idle)
            }
            _ = try await manager.client(for: connection)
            guard let client = await manager.rest(for: connection.id) else {
                throw ConnectionUnavailable(phase: await manager.phase(of: connection.id))
            }
            return client
        }

        private static func loadMessage(for error: any Error) -> String {
            if let restError = error as? RESTError, restError == .unauthorized {
                return "Sign in again to see automations."
            }
            if error is ConnectionUnavailable {
                return "Connect to the server to see automations."
            }
            return "Could not load automations. Pull down to try again."
        }

        /// What to tell the user when a change fails: the server's own words when it gave some, else `fallback`.
        static func failureText(_ error: any Error, fallback: String) -> String {
            if let restError = error as? RESTError, case .http(_, let detail?) = restError, !detail.isEmpty {
                return detail
            }
            return fallback
        }

        /// A model with fixed jobs, for previews. It makes no calls.
        public static func preview(_ jobs: [CronJob]) -> AutomationsModel {
            let model = AutomationsModel(connections: .preview([]))
            model.jobs = jobs
            model.hasLoaded = true
            return model
        }
    }
#endif
