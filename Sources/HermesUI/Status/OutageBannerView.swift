#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The glass banner above the composer of an online chat that cannot reach its server. Its actions come from
    /// `OutageBanner`. "Continue in a new Local chat" opens a different chat with the draft; this chat never moves.
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
                HStack(spacing: 8) {
                    ForEach(OutageBanner.actions, id: \.self) { action in
                        Button(action.title) {
                            switch action {
                            case .tryAgain: onTryAgain()
                            case .continueInNewLocalChat: onContinueInNewLocalChat()
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(
                            action == .tryAgain ? "outage.tryAgain" : "outage.continueLocal")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.outageBanner")
        }
    }
#endif
