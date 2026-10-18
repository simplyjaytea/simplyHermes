#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// One read-only answer of an assistant page: the panel it fills, and how to fetch it from the server.
    struct SettingsAssistantRead: Sendable {
        let id: String
        let title: String
        let footer: String?
        let fetch: @Sendable (RESTClient) async throws -> JSONValue

        init(
            id: String, title: String, footer: String? = nil,
            fetch: @escaping @Sendable (RESTClient) async throws -> JSONValue
        ) {
            self.id = id
            self.title = title
            self.footer = footer
            self.fetch = fetch
        }
    }

    /// One section of an assistant page: the rows of an answer, or why the answer could not be read.
    struct SettingsAssistantPanel: Identifiable, Equatable {
        let id: String
        var title: String
        var footer: String?
        var rows: [SettingsAssistantRow] = []
        var errorText: String?
        /// False until the first answer or error arrives, so the panel shows a spinner rather than an empty list.
        var isLoaded = false
    }

    /// An assistant settings page and the server it talks to (WP-53d). Nothing is cached: each visit reads the server.
    @MainActor
    @Observable
    final class SettingsAssistantModel {
        private(set) var panels: [SettingsAssistantPanel]
        private(set) var isLoading = false
        /// Set when the server could not be reached or a change failed. Rows already on screen stay.
        private(set) var errorText: String?
        /// Confirms the last change, for example "Memory was reset."
        private(set) var noticeText: String?

        @ObservationIgnored private let connections: ConnectionsModel?
        @ObservationIgnored private let reads: [SettingsAssistantRead]

        init(connections: ConnectionsModel?, reads: [SettingsAssistantRead]) {
            self.connections = connections
            self.reads = reads
            panels = reads.map { read in
                SettingsAssistantPanel(id: read.id, title: read.title, footer: read.footer)
            }
        }

        /// The panel with `id`, when the page has it.
        func panel(_ id: String) -> SettingsAssistantPanel? {
            panels.first { $0.id == id }
        }

        /// Reads every answer of the page. A read that fails keeps its rows and shows its own error.
        func load() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await client()
                for read in reads {
                    do {
                        let answer = try await read.fetch(rest)
                        update(read.id) { panel in
                            panel.rows = SettingsAssistantRows.rows(for: answer)
                            panel.errorText = nil
                            panel.isLoaded = true
                        }
                    } catch {
                        if error is CancellationError { return }
                        update(read.id) { panel in
                            panel.errorText = SettingsAssistantErrorText.message(for: error)
                            panel.isLoaded = true
                        }
                    }
                }
                errorText = nil
            } catch {
                if error is CancellationError { return }
                errorText = SettingsAssistantErrorText.message(for: error)
                // Nothing will arrive for these panels, so they stop showing a spinner.
                for index in panels.indices {
                    panels[index].isLoaded = true
                }
            }
        }

        /// Makes a change on the active server, then reads the page again. `notice` confirms the change.
        func change<Value: Sendable>(
            _ notice: String, _ work: @Sendable (RESTClient) async throws -> Value
        ) async {
            do {
                let rest = try await client()
                _ = try await work(rest)
                noticeText = notice
                errorText = nil
            } catch {
                if error is CancellationError { return }
                noticeText = nil
                errorText = SettingsAssistantErrorText.message(for: error)
                return
            }
            await load()
        }

        /// Runs a read that is not part of the page load, such as a scan or an audit, and shows its answer as the
        /// panel `id`. A later run with the same id replaces the panel's rows.
        func showAnswer(
            panel id: String, title: String, footer: String? = nil,
            _ work: @Sendable (RESTClient) async throws -> JSONValue
        ) async {
            var panel = SettingsAssistantPanel(id: id, title: title, footer: footer)
            do {
                let rest = try await client()
                let answer = try await work(rest)
                panel.rows = SettingsAssistantRows.rows(for: answer)
            } catch {
                if error is CancellationError { return }
                panel.errorText = SettingsAssistantErrorText.message(for: error)
            }
            panel.isLoaded = true
            store(panel)
        }

        /// The REST client of the active server, connecting first when needed.
        private func client() async throws -> RESTClient {
            guard let connections, let connection = connections.active, let manager = connections.manager else {
                throw SettingsAssistantFailure.noServer
            }
            _ = try await manager.client(for: connection)
            guard let rest = await manager.rest(for: connection.id) else {
                throw SettingsAssistantFailure.noServer
            }
            return rest
        }

        private func update(_ id: String, _ change: (inout SettingsAssistantPanel) -> Void) {
            guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
            change(&panels[index])
        }

        private func store(_ panel: SettingsAssistantPanel) {
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                panels[index] = panel
            } else {
                panels.append(panel)
            }
        }

        /// A model with fixed answers and no server, for previews. `answers` maps a read id to its answer.
        static func preview(reads: [SettingsAssistantRead], answers: [String: JSONValue]) -> SettingsAssistantModel {
            let model = SettingsAssistantModel(connections: nil, reads: reads)
            model.panels = reads.map { read -> SettingsAssistantPanel in
                var panel = SettingsAssistantPanel(id: read.id, title: read.title, footer: read.footer)
                panel.rows = SettingsAssistantRows.rows(for: answers[read.id] ?? .object([:]))
                panel.isLoaded = true
                return panel
            }
            return model
        }
    }
#endif
