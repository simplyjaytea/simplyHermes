import Foundation
import HermesKit
import HermesSSH
import HermesUI
import SwiftUI

/// Test seams for the local chat UI test (WP-7, AT-2b). Everything here is compiled only in DEBUG builds, so a release
/// build can neither name a fake model nor count its own connections.
///
/// - `-uiTestLocalExecutor=<name>` answers local chats with a fixed string that names the fake.
/// - `-uiTestNetworkTrap` shows the connections the app has opened, counted per transport in `NetworkTrap`: the total in
///   `uiTest.networkRequests`, the per-site counts in `uiTest.networkSites`.
/// - `-uiTestNetworkProbe` (with the trap) opens one real connection per transport at launch, each to the closed local
///   port 127.0.0.1:9. The UI test uses it as a positive control: every site must read at least 1, or the zero a local
///   chat reports means nothing.
/// - `-uiTestPersistentCache` keeps the chat list on disk across launches, in a file of its own (`uitest-cache.sqlite`),
///   even when the launch skips onboarding. `-uiTestResetCache` deletes that file before the first open.
enum UITestSeams {
    #if DEBUG
        private static let executorPrefix = "-uiTestLocalExecutor="
        private static let trapFlag = "-uiTestNetworkTrap"
        private static let probeFlag = "-uiTestNetworkProbe"
        private static let persistentFlag = "-uiTestPersistentCache"
        private static let resetFlag = "-uiTestResetCache"
        private static let gatewayToggleFlag = "-uiTestGatewayToggle"
        nonisolated(unsafe) private static var didResetCache = false

        private static var arguments: [String] { ProcessInfo.processInfo.arguments }

        /// The test-only cache file, when the launch asks for a persistent cache; nil otherwise, so the app keeps its
        /// usual choice. A reset deletes the file, with its write-ahead log, once per process.
        static var persistentCacheURL: URL? {
            guard arguments.contains(persistentFlag),
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("simplyHermes", isDirectory: true)
            else { return nil }
            let url = folder.appendingPathComponent("uitest-cache.sqlite")
            if arguments.contains(resetFlag), !didResetCache {
                didResetCache = true
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
                }
            }
            return url
        }

        /// The fake model's name, from `-uiTestLocalExecutor=<name>`.
        static var localExecutorName: String? {
            arguments.first { $0.hasPrefix(executorPrefix) }.map { String($0.dropFirst(executorPrefix.count)) }
        }

        /// Runs the positive control when the launch arguments ask for it.
        static func install() {
            guard arguments.contains(probeFlag) else { return }
            Task { await probeEverySite() }
        }

        /// One real connection per transport, all to a closed loopback port, so each fails at once and nothing leaves
        /// the phone. The counter moves when a transport opens, before the connection fails.
        private static func probeEverySite() async {
            let closed = URL(string: "http://127.0.0.1:9/")!
            let closedSocket = URL(string: "ws://127.0.0.1:9/")!
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let probe = HTTPRequest(method: "GET", url: closed, timeout: 2)
                    _ = try? await URLSessionHTTPTransport(timeout: 2).send(probe)
                }
                group.addTask {
                    _ = try? await URLSessionWebSocketTransport().connect(url: closedSocket, headers: [:])
                }
                group.addTask {
                    _ = try? await URLSessionTerminalSocketTransport().connect(url: closedSocket, headers: [:])
                }
                group.addTask {
                    let configuration = URLSessionModelFileDownloader.defaultConfiguration()
                    configuration.waitsForConnectivity = false
                    let downloader = URLSessionModelFileDownloader(configuration: configuration)
                    _ = try? await downloader.download(
                        from: closed.appendingPathComponent("probe.bin"), resumeData: nil, progress: { _ in })
                }
                group.addTask {
                    let configuration = SSHConfiguration(
                        host: "127.0.0.1", port: 9, username: "probe", credential: .password("probe"),
                        hostKey: .pinned(openSSHKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIProbeOnly"),
                        ownershipID: "00000000000000000000000000000000", connectTimeout: .seconds(3))
                    _ = try? await SSHTunnel(configuration: configuration).start()
                }
            }
        }

        /// An answerer whose every reply is the fixed text `Reply from <name>`, stamped with the fake's name.
        static func answerer(named name: String) -> @Sendable () -> any LocalChatAnswerer {
            {
                FixedModelAnswerer(
                    identity: .downloaded(id: "ui-test-\(name)", displayName: name),
                    executor: FixedStringExecutor(name: name))
            }
        }

        /// The hidden readouts of connections opened: the total, and the count per site. Empty unless the trap is on.
        @ViewBuilder
        static func readout() -> some View {
            if arguments.contains(trapFlag) {
                VStack {
                    Text("\(NetworkTrap.count)")
                        .accessibilityIdentifier("uiTest.networkRequests")
                    Text(NetworkTrap.summary)
                        .accessibilityIdentifier("uiTest.networkSites")
                }
                .font(.system(size: 1))
                .opacity(0.01)
            }
            if arguments.contains(gatewayToggleFlag) {
                // Below the status bar and the navigation bar: a tap in that top strip goes to the system, not the app.
                GatewayToggle()
                    .padding(.top, 110)
                    .padding(.leading, 12)
            }
        }

        /// Replies the fake on-device executor has given. A server chat must leave it at zero.
        nonisolated(unsafe) private static var localReplies = 0
        private static let replyLock = NSLock()

        static var localReplyCount: Int {
            replyLock.withLock { localReplies }
        }

        static func countLocalReply() {
            replyLock.withLock { localReplies += 1 }
        }
    #else
        static func install() {}

        /// Release builds never keep a test cache.
        static var persistentCacheURL: URL? { nil }

        @ViewBuilder
        static func readout() -> some View {
            EmptyView()
        }
    #endif
}

#if DEBUG
    /// Answers with a fixed string, so a UI test can read which fake answered.
    struct FixedStringExecutor: LocalModelExecutor {
        let name: String

        var availability: LocalModelAvailability { .available }

        func respond(instructions: String, prompt: String) async throws -> String {
            UITestSeams.countLocalReply()
            return "Reply from \(name)"
        }
    }

    /// The gateway switch for WP-8 AT-1b and AT-3b (`-uiTestGatewayToggle`). Stopping the gateway makes new HTTP and
    /// WebSocket connections refuse, and sets the network path to none, so the chat shows "Can't reach" at once.
    /// Starting it does both in reverse. The button's label shows the next action.
    struct GatewayToggle: View {
        @State private var stopped = NetworkTrap.isGatewayStopped

        var body: some View {
            VStack(alignment: .leading) {
                Button(stopped ? "Start gateway" : "Stop gateway") {
                    stopped.toggle()
                    NetworkTrap.setGatewayStopped(stopped)
                    NetworkMonitor.shared.setPathForTesting(stopped ? .unsatisfied : .satisfied)
                    // An outage drops the live socket too; without this the open chat keeps sending over it.
                    if stopped { URLSessionWebSocketTransport.dropOpenSockets() }
                }
                .accessibilityIdentifier("uiTest.gatewayToggle")
                Text("\(UITestSeams.localReplyCount)")
                    .accessibilityIdentifier("uiTest.localReplies")
            }
            .font(.caption)
        }
    }
#endif
