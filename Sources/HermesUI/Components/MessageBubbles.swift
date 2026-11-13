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
            modifier(BubbleRowLayout(side: side))
        }
    }

    /// At the accessibility text sizes the free side shrinks, so large text gets the width instead of a gap.
    private struct BubbleRowLayout: ViewModifier {
        let side: BubbleSide
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity, alignment: side == .trailing ? .trailing : .leading)
                .padding(
                    side == .trailing ? .leading : .trailing,
                    dynamicTypeSize.isAccessibilitySize
                        ? HermesMetrics.bubbleSideInset / 4 : HermesMetrics.bubbleSideInset)
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
        private let rendersMarkdown: Bool
        @Environment(\.hermesPalette) private var palette

        public init(role: Role, text: String, rendersMarkdown: Bool = false) {
            self.role = role
            self.text = text
            self.rendersMarkdown = rendersMarkdown
        }

        public var body: some View {
            Text(rendersMarkdown ? InlineMarkdown.attributed(text) : AttributedString(text))
                .font(HermesFont.bubble)
                .foregroundStyle(role == .user ? palette.onAccent : palette.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                .padding(.vertical, HermesMetrics.bubbleVerticalPadding)
                .background(role == .user ? palette.outgoingBubble : palette.incomingBubble, in: bubbleShape)
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
        @Environment(\.hermesPalette) private var palette

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
                        .foregroundStyle(palette.secondaryText)
                    if let duration {
                        Spacer(minLength: 8)
                        Text(duration)
                            .font(HermesFont.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Text(output)
                    .font(HermesFont.codeSmall)
                    .foregroundStyle(palette.primaryText)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 10)
            .background(palette.incomingBubble, in: bubbleShape)
            .accessibilityElement(children: .combine)
            .bubbleRow(.leading)
        }
    }

    /// A command waiting for the user's approval, with Deny and Approve buttons.
    public struct ApprovalBubble: View {
        private let command: String
        private let isEnabled: Bool
        private let allowsFeedback: Bool
        private let onDeny: () -> Void
        private let onApprove: () -> Void

        @State private var appeared = false
        @State private var denyCount = 0
        @State private var approveCount = 0
        @Environment(\.hermesPalette) private var palette

        public init(
            command: String,
            isEnabled: Bool = true,
            allowsFeedback: Bool = true,
            onDeny: @escaping () -> Void,
            onApprove: @escaping () -> Void
        ) {
            self.command = command
            self.isEnabled = isEnabled
            self.allowsFeedback = allowsFeedback
            self.onDeny = onDeny
            self.onApprove = onApprove
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Approve this command?")
                    .font(HermesFont.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(command)
                    .font(HermesFont.code)
                    .foregroundStyle(palette.primaryText)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Deny") {
                        denyCount += 1
                        onDeny()
                    }
                    .buttonStyle(HermesButtonStyle(.secondary))
                    .disabled(!isEnabled)
                    Button("Approve") {
                        approveCount += 1
                        onApprove()
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(!isEnabled)
                }
            }
            .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
            .padding(.vertical, 10)
            .background(palette.incomingBubble, in: bubbleShape)
            .bubbleRow(.leading)
            .onAppear {
                if allowsFeedback { appeared = true }
            }
            .hermesFeedback(.approvalNeeded, trigger: allowsFeedback && appeared)
            .hermesFeedback(.denied, trigger: allowsFeedback ? denyCount : 0)
            .hermesFeedback(.approved, trigger: allowsFeedback ? approveCount : 0)
        }
    }
#endif
