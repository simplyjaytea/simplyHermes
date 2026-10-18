#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings > Tools & MCP > Capabilities: whether Computer Use can act on the Hermes server. Read only (WP-53b).
    public struct CapabilityStatusView: View {
        private let connections: ConnectionsModel
        @State private var model: CapabilityStatusModel

        public init(connections: ConnectionsModel) {
            self.connections = connections
            _model = State(initialValue: CapabilityStatusModel(connections: connections))
        }

        init(connections: ConnectionsModel, model: CapabilityStatusModel) {
            self.connections = connections
            _model = State(initialValue: model)
        }

        public var body: some View {
            List {
                if let status = model.status {
                    summarySection(status)
                }
                if let errorText = model.errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HermesColor.destructive)
                    }
                }
            }
            .navigationTitle("Capabilities")
            .overlay { emptyState }
            .refreshable { await model.refresh() }
            .task(id: connections.active?.id) { await model.refresh() }
        }

        private func summarySection(_ status: CapabilityComputerUseStatus) -> some View {
            Section {
                LabeledContent {
                    Text(platformName(status.platform))
                } label: {
                    Text("Computer")
                }
                LabeledContent {
                    Text(yesNo(status.platformSupported))
                } label: {
                    Text("Supported")
                }
                LabeledContent {
                    Text(installedText(status.installed))
                } label: {
                    Text("Driver")
                }
                LabeledContent {
                    Text(grantText(status.canGrant))
                } label: {
                    Text("Permission grant")
                }
            } header: {
                Text("Computer Use")
            } footer: {
                Text(footer(status))
            }
        }

        private func yesNo(_ value: Bool?) -> String {
            guard let value else { return "Unknown" }
            return value ? "Yes" : "No"
        }

        private func installedText(_ value: Bool?) -> String {
            guard let value else { return "Unknown" }
            return value ? "Installed" : "Not installed"
        }

        private func grantText(_ value: Bool?) -> String {
            guard let value else { return "Unknown" }
            return value ? "Can be requested" : "Not available"
        }

        private func platformName(_ platform: String?) -> String {
            switch platform ?? "" {
            case "darwin": return "macOS"
            case "win32": return "Windows"
            case "linux": return "Linux"
            case "": return "Unknown"
            default: return platform ?? "Unknown"
            }
        }

        private func footer(_ status: CapabilityComputerUseStatus) -> String {
            if status.platformSupported == false {
                return "Computer Use doesn't run on this server's operating system."
            }
            return "Read from the Hermes server. This screen changes nothing."
        }

        @ViewBuilder private var emptyState: some View {
            if model.status == nil && model.errorText == nil {
                if connections.active == nil {
                    ContentUnavailableView(
                        "No server", systemImage: "server.rack", description: Text("Add a server under Servers first."))
                } else if model.isLoading {
                    ProgressView()
                }
            }
        }
    }

    #Preview("Capabilities, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack { CapabilityStatusView(connections: .preview(), model: .preview()) }
    }

    #Preview("Capabilities, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack { CapabilityStatusView(connections: .preview(), model: .preview()) }
    }

    #Preview("Capabilities, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack { CapabilityStatusView(connections: .preview(), model: .preview()) }
    }

    #Preview("Capabilities, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack { CapabilityStatusView(connections: .preview(), model: .preview()) }
    }
#endif
