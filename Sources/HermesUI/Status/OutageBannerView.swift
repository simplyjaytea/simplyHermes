#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The glass banner above the composer of an online chat that cannot reach its server. Its actions come from
    /// `OutageBanner`. "Continue in a new Local chat" opens a different chat with the draft, and this chat's draft moves
    /// with it; this chat never switches.
    struct OutageBannerView: View {
        let serverName: String
        let onTryAgain: () -> Void
        let onContinueInNewLocalChat: () -> Void
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(OutageBanner.title(serverName: serverName), systemImage: "wifi.exclamationmark")
                    .font(HermesFont.headline)
                    .foregroundStyle(palette.primaryText)
                Text(OutageBanner.message)
                    .font(HermesFont.subheadline)
                    .foregroundStyle(palette.secondaryText)
                // Side by side at normal sizes; stacked when the labels no longer fit (large Dynamic Type, outer screen).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: HermesMetrics.bannerRadius, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.outageBanner")
        }

        @ViewBuilder
        private var buttons: some View {
            ForEach(OutageBanner.actions, id: \.self) { action in
                Button(action.title) {
                    switch action {
                    case .tryAgain: onTryAgain()
                    case .continueInNewLocalChat: onContinueInNewLocalChat()
                    }
                }
                .buttonStyle(HermesButtonStyle(action == .tryAgain ? .primary : .tinted, fillsWidth: false))
                .accessibilityIdentifier(action == .tryAgain ? "outage.tryAgain" : "outage.continueLocal")
            }
        }
    }
#endif
