#if canImport(UIKit)
    import Foundation
    import HermesKit
    import OSLog
    import UIKit

    /// Gathers the diagnostics block for a bug report: app and system versions, the device, the shell layout, the
    /// active connection and the app's recent log.
    @MainActor
    public enum DiagnosticsCollector {
        /// The `Logger` subsystem every simplyHermes log line uses.
        public static let logSubsystem = "com.simplyjaytea.simplyhermes"

        /// Everything except the log, which ``recentLogLines(within:limit:)`` reads off the main actor.
        public static func collect(
            layout: DisplayLayout?, posture: DevicePosture?, connections: ConnectionsModel?, logLines: [String] = []
        ) -> BugReportDiagnostics {
            let info = Bundle.main.infoDictionary ?? [:]
            let device = UIDevice.current
            var diagnostics = BugReportDiagnostics(
                appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
                build: info["CFBundleVersion"] as? String ?? "?",
                system: "\(device.systemName) \(device.systemVersion)",
                device: modelIdentifier(),
                layout: layout?.rawValue,
                posture: posture?.rawValue,
                logLines: logLines)
            if let connections, let active = connections.active {
                diagnostics.connectionKind = active.isSSH ? "ssh" : "gateway"
                let phase = connections.phase(of: active.id)
                diagnostics.connectionState = describe(phase)
                if case .connected(let summary) = phase {
                    diagnostics.serverVersion = [summary.serverVersion, summary.releaseDate]
                        .compactMap { $0 }.joined(separator: ", ")
                }
            }
            return diagnostics
        }

        /// Strings that identify the user's servers, removed from diagnostics on top of the redactor's patterns.
        public static func privateValues(_ connections: ConnectionsModel?) -> [String] {
            guard let connections else { return [] }
            var values: [String] = []
            for connection in connections.connections {
                values.append(connection.name)
                values.append(connection.address)
                switch connection.kind {
                case .gateway(let settings):
                    if let host = settings.endpoint.baseURL.host { values.append(host) }
                case .ssh(let settings):
                    values += [settings.host, settings.username]
                }
                if case .connected(let summary) = connections.phase(of: connection.id), let user = summary.signedInAs {
                    values.append(user)
                }
            }
            return values
        }

        /// The app's own log lines from the last `within` seconds, oldest first, at most `limit`.
        /// Runs off the main actor: reading the log store can take a moment.
        public nonisolated static func recentLogLines(within: TimeInterval = 30 * 60, limit: Int = 400) async
            -> [String]
        {
            await Task.detached(priority: .userInitiated) {
                guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
                let start = store.position(date: Date().addingTimeInterval(-within))
                let predicate = NSPredicate(format: "subsystem == %@", logSubsystem)
                guard let entries = try? store.getEntries(at: start, matching: predicate) else { return [] }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withTime, .withColonSeparatorInTime, .withFractionalSeconds]
                var lines: [String] = []
                for case let entry as OSLogEntryLog in entries {
                    lines.append(
                        "\(formatter.string(from: entry.date)) [\(entry.category)] \(level(entry.level)) "
                            + entry.composedMessage)
                }
                return Array(lines.suffix(limit))
            }.value
        }

        private nonisolated static func level(_ level: OSLogEntryLog.Level) -> String {
            switch level {
            case .debug: "debug"
            case .info: "info"
            case .notice: "notice"
            case .error: "error"
            case .fault: "fault"
            default: "log"
            }
        }

        private static func describe(_ phase: ConnectionPhase) -> String {
            switch phase {
            case .idle: "idle"
            case .unlocking: "unlocking"
            case .openingTunnel: "opening tunnel"
            case .checkingServer: "checking server"
            case .connecting: "connecting"
            case .connected: "connected"
            case .reconnecting(let attempt): "reconnecting (attempt \(attempt))"
            case .signInRequired: "sign-in required"
            case .updateRequired(let found): "update required (\(found))"
            case .failed(let failure): "failed (\(failure))"
            }
        }

        /// Such as `iPhone19,1`; the simulator reports the model it stands in for.
        private static func modelIdentifier() -> String {
            if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
                return simulated + " (simulator)"
            }
            var system = utsname()
            uname(&system)
            return withUnsafeBytes(of: &system.machine) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
    }
#endif
