import HermesKit
import HermesUI
import SwiftUI

@main
struct HermesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("simplyHermes")
                .font(.largeTitle.bold())
            Text("Hermes \(HermesKit.minimumServerVersion)+")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("root")
    }
}
