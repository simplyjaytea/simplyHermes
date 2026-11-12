import Foundation
import HermesKit
import SwiftUI

/// The gateway switch for WP-8 AT-1b and AT-3b (`-uiTestGatewayToggle`). It stops and starts network transports, so it
/// lives here and not in `LocalChat/UITestSeams.swift`: the local-chat sources hold no network code (G2,
/// `LocalChatNetworkGuardTests`). Compiled only in DEBUG builds.
enum UITestGatewayToggle {
    #if DEBUG
        private static let flag = "-uiTestGatewayToggle"

        /// The switch, when the launch asks for it. Below the status bar and the navigation bar: a tap in that top
        /// strip goes to the system, not the app.
        @ViewBuilder
        static func overlay() -> some View {
            if ProcessInfo.processInfo.arguments.contains(flag) {
                GatewayToggle()
                    .padding(.top, 110)
                    .padding(.leading, 12)
            }
        }
    #else
        @ViewBuilder
        static func overlay() -> some View {
            EmptyView()
        }
    #endif
}

#if DEBUG
    /// Stopping the gateway makes new HTTP and WebSocket connections refuse, and sets the network path to none, so the
    /// chat shows "Can't reach" at once. Starting it does both in reverse. The button's label shows the next action.
    private struct GatewayToggle: View {
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
