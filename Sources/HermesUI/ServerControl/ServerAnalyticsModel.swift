#if canImport(UIKit)
    import HermesKit
    import Observation

    /// One group of usage rows, such as one model. Its title is the group's `Model` value when it has one.
    public struct ServerAnalyticsGroup: Identifiable, Equatable, Sendable {
        /// Position in the answer.
        public var id: Int
        /// Name to show.
        public var title: String
        /// The rows of the group.
        public var rows: [ServerStatsRow]
    }

    /// The Usage screen (Tools > Usage): totals and per-model rows for a period (WP-54). The figures are listed,
    /// not charted, so the screen needs no chart framework.
    @MainActor
    @Observable
    public final class ServerAnalyticsModel {
        /// The top-level figures.
        public private(set) var totals: [ServerStatsRow] = []
        /// One group per model, from the per-model list of the answer.
        public private(set) var groups: [ServerAnalyticsGroup] = []
        public private(set) var isLoading = false
        /// Set when the read failed. The last figures stay on screen.
        public private(set) var errorText: String?

        @ObservationIgnored private let connections: ConnectionsModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
        }

        /// Reads the usage and the per-model figures for `window`.
        public func load(_ window: ServerAnalyticsWindow) async {
            guard connections.manager != nil else { return }
            guard let connection = connections.active, let backend = serverControlBackend(connections, connection)
            else {
                errorText = "Choose a server in Settings > Servers."
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                let rest = try await backend.rest()
                let usage = try await rest.analyticsUsage(days: window.rawValue)
                // The per-model answer is preferred; the usage answer may list the same groups.
                let models = try? await rest.analyticsModels(days: window.rawValue)
                totals = ServerAnalyticsRows.totals(from: usage)
                groups = Self.makeGroups(from: models ?? usage)
                errorText = nil
            } catch {
                errorText = ServerControlError.describe(error)
            }
        }

        static func makeGroups(from answer: JSONValue) -> [ServerAnalyticsGroup] {
            ServerAnalyticsRows.groups(from: answer).enumerated().map { index, rows in
                let model = rows.first { $0.label == "Model" }?.value
                return ServerAnalyticsGroup(id: index, title: model ?? "Item \(index + 1)", rows: rows)
            }
        }

        /// A model with sample figures, for previews.
        static func preview(errorText: String? = nil) -> ServerAnalyticsModel {
            let model = ServerAnalyticsModel(connections: .preview())
            model.totals = [
                ServerStatsRow(label: "Period days", value: "30"),
                ServerStatsRow(label: "Totals total api calls", value: "188"),
                ServerStatsRow(label: "Totals total sessions", value: "42"),
            ]
            model.groups = [
                ServerAnalyticsGroup(
                    id: 0, title: "fake-model",
                    rows: [
                        ServerStatsRow(label: "Model", value: "fake-model"),
                        ServerStatsRow(label: "Api calls", value: "188"),
                    ]),
                ServerAnalyticsGroup(
                    id: 1, title: "small-model",
                    rows: [
                        ServerStatsRow(label: "Model", value: "small-model"),
                        ServerStatsRow(label: "Api calls", value: "123"),
                    ]),
            ]
            model.errorText = errorText
            return model
        }
    }
#endif
