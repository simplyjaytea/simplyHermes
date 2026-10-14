import HermesKit
import HermesUI
import SwiftUI

@main
struct HermesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(HermesColor.accent)
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("simplyHermes")
                    .font(.largeTitle.bold())
                Text("Hermes \(HermesKit.minimumServerVersion)+")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink("Component gallery") {
                    ScrollView { ComponentGallery() }
                        .navigationTitle("Components")
                }
                .padding(.top, 16)
            }
            .accessibilityIdentifier("root")
        }
    }
}
