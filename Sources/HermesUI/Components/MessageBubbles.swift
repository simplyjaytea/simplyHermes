#if canImport(UIKit)
    import SwiftUI

    /// Which side of the transcript a bubble sits on.
    public enum BubbleSide: Sendable {
        case leading
        case trailing
    }

    extension View {
        /// Places a bubble on its side of the transcript and keeps the far side free.
        public func bubbleRow(_ side: BubbleSide) -> some View {
            frame(maxWidth: .infinity, alignment: side == .trailing ? .trailing : .leading)
                .padding(side == .trailing ? .leading : .trailing, HermesMetrics.bubbleSideInset)
        }
    }

    private let bubbleShape = RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)

    /// A chat message in bubble style (chat style A, chosen by JT on 2026-10-14).
    public struct MessageBubble: View {
        public enum Role: Sendable {
            case user
            case assistant
        }

        private let role: Role
        private let text: String

        public init(role: Role, text: String) {
            self.role = role
            self.text = text
        }

        public var body: some View {
            Text(text)
                .font(HermesFont.bubble)
                .foregroundStyle(role == .user ? HermesColor.onAccent : HermesColor.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                .padding(.vertical, HermesMetrics.bubbleVerticalPadding)
                .background(role == .user ? HermesColor.outgoingBubble : HermesColor.incomingBubble, in: bubbleShape)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(role == .user ? Text("You") : Text("Hermes"))
                .accessibilityValue(Text(text))
                .bubbleRow(role == .user ? .trailing : .leading)
        }
    }

    /// A tool call and its output, shown in a grey bubble in monospace.
    public struct ToolOutputBubble: View {
        private let command: String
        private let output: String
        private let duration: String?

        public init(command: String, output: String, duration: String? = nil) {
            self.command = command
            self.output = output
            self.duration = duration
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: "$ \(command)")
                        .font(HermesFont.codeSmall)
                        .foregroundStyle(HermesColor.secondaryText)
                    if let duration {
                        Spacer(minLength: 8)
                        Text(duration)
                            .font(HermesFont.caption)
                            .foregroundStyle(HermesColor.secondaryText)
                    }
                }
                Text(output)
                    .font(HermesFont.codeSmall)
                    .foregroundStyle(HermesColor.primaryText)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 10)
            .background(HermesColor.incomingBubble, in: bubbleShape)
            .accessibilityElement(children: .combine)
            .bubbleRow(.leading)
        }
    }

    /// A command waiting for the user's approval, with Deny and Approve buttons.
    public struct ApprovalBubble: View {
        private let command: String
        private let onDeny: () -> Void
        private let onApprove: () -> Void

        @State private var appeared = false
        @State private var denyCount = 0
        @State private var approveCount = 0

        public init(command: String, onDeny: @escaping () -> Void, onApprove: @escaping () -> Void) {
            self.command = command
            self.onDeny = onDeny
            self.onApprove = onApprove
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Approve this command?")
                    .font(HermesFont.subheadline.weight(.semibold))
                Text(command)
                    .font(HermesFont.code)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Deny") {
                        denyCount += 1
                        onDeny()
                    }
                    .buttonStyle(HermesButtonStyle(.secondary))
                    Button("Approve") {
                        approveCount += 1
                        onApprove()
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 10)
            .background(HermesColor.incomingBubble, in: bubbleShape)
            .bubbleRow(.leading)
            .onAppear { appeared = true }
            .hermesFeedback(.approvalNeeded, trigger: appeared)
            .hermesFeedback(.denied, trigger: denyCount)
            .hermesFeedback(.approved, trigger: approveCount)
        }
    }
#endif
