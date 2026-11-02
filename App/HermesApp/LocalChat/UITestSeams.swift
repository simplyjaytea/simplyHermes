import Foundation
import HermesKit
import HermesUI
import SwiftUI

/// Test seams for the local chat UI test (WP-7, AT-2b). Everything here is compiled only in DEBUG builds, so a release
/// build can neither name a fake model nor count its own connections.
///
/// - `-uiTestLocalExecutor=<name>` answers local chats with a fixed string that names the fake.
/// - `-uiTestNetworkTrap` shows the number of connections the app has opened (every HTTP request, WebSocket, terminal
///   socket and SSH connection, counted in `NetworkTrap`) in the hidden element `uiTest.networkRequests`.
/// - `-uiTestNetworkProbe` (with the trap) opens one real HTTP connection at launch, to a closed local port. The UI test
///   uses it as a positive control: the counter must read at least 1 when the probe runs, or the zero it reports for a
///   local chat means nothing.
enum UITestSeams {
    #if DEBUG
        private static let executorPrefix = "-uiTestLocalExecutor="
        private static let trapFlag = "-uiTestNetworkTrap"
        private static let probeFlag = "-uiTestNetworkProbe"

        private static var arguments: [String] { ProcessInfo.processInfo.arguments }

        /// The fake model's name, from `-uiTestLocalExecutor=<name>`.
        static var localExecutorName: String? {
            arguments.first { $0.hasPrefix(executorPrefix) }.map { String($0.dropFirst(executorPrefix.count)) }
        }

        /// Runs the positive control when the launch arguments ask for it.
        static func install() {
            guard arguments.contains(probeFlag) else { return }
            Task {
                let probe = HTTPRequest(method: "GET", url: URL(string: "http://127.0.0.1:9/")!, timeout: 2)
                _ = try? await URLSessionHTTPTransport(timeout: 2).send(probe)
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

        /// The hidden readout of connections opened. It is empty unless the trap is on.
        @ViewBuilder
        static func readout() -> some View {
            if arguments.contains(trapFlag) {
                Text("\(NetworkTrap.count)")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("uiTest.networkRequests")
            }
        }
    #else
        static func install() {}

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
            "Reply from \(name)"
        }
    }
#endif
