#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// A failed turn: which layer failed, the server's text, and what the user can do (plan WP-30).
    struct ErrorCard: View {
        let error: ChatError
        let isLast: Bool
        @Bindable var chat: LiveChatModel
        @State private var copyCount = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(HermesFont.subheadline.weight(.semibold))
                    .foregroundStyle(HermesColor.destructive)
                Text(error.message)
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(6)
                HStack(spacing: 8) {
                    if isLast, error.isRetryable, !chat.isRunning {
                        Button("Retry") { chat.retry() }
                            .buttonStyle(HermesButtonStyle(.primary))
                            .accessibilityIdentifier("error.retry")
                        if let when = error.retryAt, when > .now {
                            if chat.retryAt != nil {
                                Button("Cancel retry") { chat.cancelScheduledRetry() }
                                    .buttonStyle(HermesButtonStyle(.secondary))
                            } else {
                                Button("Retry at \(when.formatted(date: .omitted, time: .shortened))") {
                                    chat.scheduleRetry(at: when)
                                }
                                .buttonStyle(HermesButtonStyle(.secondary))
                            }
                        }
                    }
                    Button(copyCount > 0 ? "Copied" : "Copy") {
                        UIPasteboard.general.string = error.message
                        copyCount += 1
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 10)
            .background(
                HermesColor.destructive.opacity(0.12),
                in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
            )
            .bubbleRow(.leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("error.card")
        }

        private var title: LocalizedStringKey {
            switch error.kind {
            case .rateLimit: "Rate limit reached"
            case .authentication: "The provider refused the key"
            case .overloaded: "The provider is overloaded"
            case .contextTooLong: "The conversation is too long for this model"
            case .timeout: "The request timed out"
            case .offline: "Connection problem"
            case .unknown: error.layer == .tool ? "A tool failed" : "Something went wrong"
            }
        }

        private var icon: String {
            switch error.layer {
            case .provider: "exclamationmark.triangle"
            case .network: "wifi.exclamationmark"
            case .tool: "wrench.and.screwdriver"
            case .unknown: "exclamationmark.circle"
            }
        }
    }
#endif
