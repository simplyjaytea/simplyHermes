import HermesKit
import HermesUI
import Observation
import SwiftUI

/// Where the Share sheet is: reading what was shared, ready for the user, or sent to the outbox but not yet opened.
@MainActor
@Observable
final class ShareFlow {
    enum Phase {
        case loading
        case ready(ShareSheetModel)
        /// The message is in the outbox but the app could not be opened from here. It sends the next time the app opens.
        case savedForLater
    }

    var phase = Phase.loading
    /// Set when the share could not be written. The sheet stays open so nothing is lost.
    var problem: String?
}

struct ShareRootView: View {
    @Bindable var flow: ShareFlow
    let onCancel: () -> Void
    let onSend: () -> Void
    let onDone: () -> Void

    var body: some View {
        Group {
            switch flow.phase {
            case .loading:
                ProgressView("Getting ready")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HermesColor.groupedBackground)
            case .ready(let model):
                ShareSheetView(model: model, onCancel: onCancel, onSend: onSend)
            case .savedForLater:
                savedForLater
            }
        }
        .tint(HermesColor.accent)
        .alert(
            "Could not save this",
            isPresented: Binding(get: { flow.problem != nil }, set: { if !$0 { flow.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(flow.problem ?? "")
        }
    }

    private var savedForLater: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(HermesColor.statusConnected)
                    .accessibilityHidden(true)
                Text("Saved")
                    .font(HermesFont.headline)
                Text("It is sent the next time you open simplyHermes.")
                    .font(HermesFont.subheadline)
                    .foregroundStyle(HermesColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HermesColor.groupedBackground)
            .navigationTitle("Send to Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("share.done")
                }
            }
        }
    }
}
