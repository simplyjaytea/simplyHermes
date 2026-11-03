import Foundation
import HermesKit
import HermesSSH

/// The positive control for the local chat UI test's network trap (WP-7, AT-2b). With `-uiTestNetworkTrap
/// -uiTestNetworkProbe`, the app opens one real connection per transport at launch, each to the closed local port
/// 127.0.0.1:9, and every site must read at least 1, or the zero a local chat reports means nothing. Moved out of
/// `LocalChat/UITestSeams.swift` so the local-chat sources hold no network code (G2). Compiled only in DEBUG builds.
enum UITestNetworkProbe {
    #if DEBUG
        private static let probeFlag = "-uiTestNetworkProbe"

        /// Runs the positive control when the launch arguments ask for it.
        static func install() {
            guard ProcessInfo.processInfo.arguments.contains(probeFlag) else { return }
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
    #else
        static func install() {}
    #endif
}
