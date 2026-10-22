import CoreSpotlight
import HermesKit
import HermesUI
import SwiftUI

/// Hooks the app's window up to ``EntryIntegration``: the Quick Entry sheet, links, Spotlight results, and the moment
/// the app becomes active.
struct IntegrationHost: ViewModifier {
    let entry: EntryIntegration
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { entry.quickEntry.isPresented },
                    set: { entry.quickEntry.isPresented = $0 })
            ) {
                QuickEntrySheet(coordinator: entry.quickEntry, hasServer: entry.hasServer) { text, target in
                    entry.sendQuickEntry(text: text, target: target)
                }
                .tint(HermesColor.accent)
            }
            .onOpenURL { url in
                entry.handle(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                entry.handle(activity: activity)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { entry.becameActive() }
            }
            .task {
                // The first activation happens before the phase changes, so the change handler never sees it.
                entry.becameActive()
            }
    }
}

extension View {
    /// Adds the Quick Entry sheet and the handlers for links, Spotlight results and activation.
    func integrationHost(_ entry: EntryIntegration) -> some View {
        modifier(IntegrationHost(entry: entry))
    }
}
