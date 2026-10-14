#if canImport(UIKit)
    import SwiftUI

    /// The message composer in bubble style: an attach button, then a rounded field with an inline send button.
    public struct Composer: View {
        @Binding private var text: String
        private let placeholder: String
        private let onAttach: () -> Void
        private let onSend: () -> Void

        @State private var sendCount = 0

        public init(
            text: Binding<String>,
            placeholder: String = "Message Hermes",
            onAttach: @escaping () -> Void = {},
            onSend: @escaping () -> Void
        ) {
            _text = text
            self.placeholder = placeholder
            self.onAttach = onAttach
            self.onSend = onSend
        }

        public var body: some View {
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HermesColor.primaryText)
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                        .background(HermesColor.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Attach"))

                HStack(alignment: .bottom, spacing: 4) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .accessibilityIdentifier("composer.field")
                        .font(HermesFont.body)
                        .lineLimit(1...6)
                        .padding(.vertical, 11)
                        .padding(.leading, 14)
                    sendButton
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(HermesColor.separator)
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hermesFeedback(.send, trigger: sendCount)
        }

        private var sendButton: some View {
            Button {
                sendCount += 1
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(HermesColor.onAccent)
                    .frame(width: 32, height: 32)
                    .background(canSend ? HermesColor.accent : HermesColor.statusOffline, in: Circle())
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
        }

        private var canSend: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
#endif
