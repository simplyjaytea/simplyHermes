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
                    if status.canGrant == true {
                        permissionsSection(status)
                    }
                    if let checks = status.checks, !checks.isEmpty {
                        checksSection(checks)
                    }
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
                    Text(yesNo(status.ready))
                } label: {
                    Text("Ready")
                }
                LabeledContent {
                    Text(platformName(status.platform))
                } label: {
                    Text("Computer")
                }
                LabeledContent {
                    Text(driverText(status))
                } label: {
                    Text("Driver")
                }
            } header: {
                Text("Computer Use")
            } footer: {
                Text(footer(status))
            }
        }

        private func permissionsSection(_ status: CapabilityComputerUseStatus) -> some View {
            Section {
                LabeledContent {
                    Text(yesNo(status.accessibility))
                } label: {
                    Text("Accessibility")
                }
                LabeledContent {
                    Text(yesNo(status.screenRecording))
                } label: {
                    Text("Screen Recording")
                }
                LabeledContent {
                    Text(yesNo(status.screenRecordingCapturable))
                } label: {
                    Text("Screen capture works")
                }
            } header: {
                Text("Permissions on the Mac")
            } footer: {
                Text(
                    "Hermes needs Accessibility and Screen Recording on the Mac that runs it. "
                        + "Grant them there in System Settings > Privacy & Security. This app can't grant them.")
            }
        }

        private func checksSection(_ checks: [CapabilityCheck]) -> some View {
            Section {
                ForEach(Array(checks.enumerated()), id: \.offset) { item in
                    checkRow(item.element)
                }
            } header: {
                Text("Checks")
            }
        }

        private func checkRow(_ check: CapabilityCheck) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(check.label ?? "Check")
                } icon: {
                    Image(systemName: symbol(check.status))
                        .foregroundStyle(color(check.status))
                }
                if let message = check.message, !message.isEmpty {
                    Text(message)
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
        }

        private func yesNo(_ value: Bool?) -> String {
            guard let value else { return "Unknown" }
            return value ? "Yes" : "No"
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

        private func driverText(_ status: CapabilityComputerUseStatus) -> String {
            if status.installed == true {
                if let version = status.version, !version.isEmpty {
                    return "Installed, version \(version)"
                }
                return "Installed"
            }
            return status.installed == false ? "Not installed" : "Unknown"
        }

        private func footer(_ status: CapabilityComputerUseStatus) -> String {
            if let error = status.error, !error.isEmpty {
                return error
            }
            if status.platformSupported == false {
                return "Computer Use doesn't run on this server's operating system."
            }
            return "Read from the Hermes server. This screen changes nothing."
        }

        private func symbol(_ status: String?) -> String {
            switch status ?? "" {
            case "ok": return "checkmark.circle.fill"
            case "fail": return "xmark.circle.fill"
            default: return "minus.circle"
            }
        }

        private func color(_ status: String?) -> Color {
            switch status ?? "" {
            case "ok": return HermesColor.statusConnected
            case "fail": return HermesColor.destructive
            default: return HermesColor.secondaryText
            }
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
