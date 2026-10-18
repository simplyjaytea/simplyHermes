#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The backend for the saved connection, or nil when the connection manager is not running (previews, offline).
    @MainActor
    func serverControlBackend(
        _ connections: ConnectionsModel, _ connection: ServerConnection?
    ) -> ServerControlBackend? {
        guard let connection, let manager = connections.manager else { return nil }
        return ServerControlBackend(manager: manager, connection: connection)
    }

    /// Label and value rows for answers the server sends without a schema.
    struct ServerStatsRowsView: View {
        let rows: [ServerStatsRow]

        var body: some View {
            ForEach(rows) { row in
                LabeledContent {
                    Text(row.value)
                        .font(HermesFont.codeSmall)
                        .textSelection(.enabled)
                } label: {
                    Text(row.label)
                }
            }
        }
    }

    /// A red line with an icon, for a failed load or action.
    struct ServerControlProblem: View {
        let text: String

        var body: some View {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(HermesColor.destructive)
            .accessibilityIdentifier("serverControl.problem")
        }
    }

    /// Spinner with a line of text, for a step that is running.
    struct ServerControlBusyLine: View {
        let text: String

        var body: some View {
            HStack(spacing: 12) {
                ProgressView()
                Text(text)
                    .foregroundStyle(HermesColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
