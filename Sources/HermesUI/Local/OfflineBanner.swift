#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A small airplane that marks an offline chat (plan Q44). The sessions list shows it on the row of an offline chat;
    /// the tab and the sidebar can too.
    public struct OfflineBadge: View {
        public init() {}

        public var body: some View {
            Image(systemName: "airplane")
                .font(HermesFont.footnote)
                .foregroundStyle(HermesColor.secondaryText)
                .accessibilityLabel("Offline chat")
                .accessibilityIdentifier("offline.badge")
        }
    }

    /// "Offline, no Hermes tools": the glass banner above the composer while the server is out of reach (plan Q44).
    /// When the on-device model cannot answer either, it says why. `onGetBetterModel` adds a "Get a better model" link;
    /// the app passes the destination (WP-65c), and without it there is no link.
    public struct OfflineBanner: View {
        private let notice: OfflineChatModel.Notice
        private let onGetBetterModel: (@MainActor () -> Void)?

        public init(notice: OfflineChatModel.Notice, onGetBetterModel: (@MainActor () -> Void)? = nil) {
            self.notice = notice
            self.onGetBetterModel = onGetBetterModel
        }

        public var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "airplane")
                    .font(HermesFont.body.weight(.semibold))
                    .foregroundStyle(HermesColor.statusWarning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HermesFont.subheadline.weight(.semibold))
                    Text(detail)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                Spacer(minLength: 4)
                if let onGetBetterModel, offersBetterModel {
                    Button("Get a better model") { onGetBetterModel() }
                        .font(HermesFont.footnote.weight(.semibold))
                        .accessibilityIdentifier("offline.betterModel")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline.banner")
        }

        private var title: LocalizedStringKey {
            switch notice {
            case .offline: "Offline, no Hermes tools"
            case .unavailable: "Offline"
            }
        }

        private var detail: LocalizedStringKey {
            switch notice {
            case .offline: "Replies come from the model on this iPhone."
            case .unavailable(.switchedOff): "On-device models are off in Settings."
            case .unavailable(.unsupported): "This iPhone can't run the on-device model."
            case .unavailable(.disabled): "Turn on Apple Intelligence in Settings to chat offline."
            case .unavailable(.notReady): "The on-device model is getting ready."
            }
        }

        /// A better model cannot help when the user turned the models off.
        private var offersBetterModel: Bool {
            notice != .unavailable(.switchedOff)
        }
    }

    /// "Send to Hermes": offered once the server is back, for the last prompt written offline (plan Q44). The
    /// on-device model's replies stay in the offline chat; only the prompt goes to the server chat.
    struct SendToHermesBar: View {
        let offer: SendToHermesOffer
        let onSend: () -> Void
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hermes is back")
                        .font(HermesFont.subheadline.weight(.semibold))
                    Text(offer.prompt)
                        .font(HermesFont.footnote)
                        .foregroundStyle(HermesColor.secondaryText)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Button("Not now", action: onDismiss)
                        .buttonStyle(HermesButtonStyle(.tinted))
                        .accessibilityIdentifier("offline.dismissOffer")
                    Button("Send to Hermes", action: onSend)
                        .buttonStyle(HermesButtonStyle(.primary))
                        .accessibilityIdentifier("offline.sendToHermes")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("offline.offer")
        }
    }

    /// What sits above the status bar of a server chat: the offline banner while the server is out of reach, and the
    /// "Send to Hermes" offer once it is back. It takes no room otherwise.
    struct OfflineBar: View {
        let chat: LiveChatModel
        /// Follows the Settings switch, so the banner changes at once when the user turns the models off or on.
        @AppStorage(OnDeviceSettings.key) private var onDeviceEnabled = true

        var body: some View {
            VStack(spacing: 0) {
                if let notice = chat.offline.notice {
                    OfflineBanner(notice: notice, onGetBetterModel: chat.offline.getBetterModel)
                        .padding(.top, 6)
                }
                if let offer = chat.offline.offer {
                    SendToHermesBar(
                        offer: offer,
                        onSend: {
                            Task {
                                if await chat.sendToHermes(offer.prompt) { chat.offline.resolveOffer(.sent) }
                            }
                        },
                        onDismiss: { chat.offline.resolveOffer(.dismissed) }
                    )
                    .padding(.top, 6)
                }
            }
            .onChange(of: onDeviceEnabled) { _, _ in chat.offline.refresh() }
        }
    }

    private struct OfflineSamples: View {
        var body: some View {
            VStack(spacing: 12) {
                OfflineBanner(notice: .offline, onGetBetterModel: {})
                OfflineBanner(notice: .unavailable(.disabled))
                OfflineBanner(notice: .unavailable(.switchedOff))
                SendToHermesBar(
                    offer: SendToHermesOffer(chatID: "c", messageID: 3, prompt: "Why did the backup job fail?"),
                    onSend: {}, onDismiss: {})
                OfflineChatTranscript(messages: OfflineSamples.messages, isReplying: true)
                HStack {
                    OfflineBadge()
                    Text("Offline chat")
                        .font(HermesFont.body)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
            .background(HermesColor.background)
        }

        static let messages: [OfflineChatMessage] = [
            OfflineChatMessage(
                chatID: "c", id: 1, role: .user, text: "How do I list the biggest folders in a directory?",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000)),
            OfflineChatMessage(
                chatID: "c", id: 2, role: .assistant, text: "Use `du -sh *` and sort the output with `sort -h`.",
                createdAt: Date(timeIntervalSince1970: 1_800_000_010)),
            OfflineChatMessage(
                chatID: "c", id: 3, role: .user, text: "Now check the backup job.",
                createdAt: Date(timeIntervalSince1970: 1_800_000_020)),
        ]
    }

    #Preview("Offline, outer", traits: .fixedLayout(width: 466, height: 678)) {
        OfflineSamples()
    }

    #Preview("Offline, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        OfflineSamples()
    }

    #Preview("Offline, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        OfflineSamples()
    }

    #Preview("Offline, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        OfflineSamples()
    }

    #Preview("Offline, outer, dark", traits: .fixedLayout(width: 466, height: 678)) {
        OfflineSamples()
            .preferredColorScheme(.dark)
    }
#endif
