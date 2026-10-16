#if canImport(UIKit)
    import SwiftUI

    /// The message composer in bubble style: an attach button, then a rounded field with an inline send button.
    public struct Composer: View {
        @Binding private var text: String
        private let placeholder: String
        private let onAttach: () -> Void
        private let onSend: () -> Void
        private let onSteer: (() -> Void)?

        @State private var sendCount = 0

        public init(
            text: Binding<String>,
            placeholder: String = "Message Hermes",
            onAttach: @escaping () -> Void = {},
            onSend: @escaping () -> Void,
            onSteer: (() -> Void)? = nil
        ) {
            _text = text
            self.placeholder = placeholder
            self.onAttach = onAttach
            self.onSend = onSend
            self.onSteer = onSteer
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
                    // The idle button uses text-safe colors: white on system gray is below 4.5:1.
                    .foregroundStyle(canSend ? HermesColor.onAccent : HermesColor.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(canSend ? HermesColor.accent : HermesColor.fill, in: Circle())
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(Text("Send"))
            .popoverTip(onSteer == nil ? nil : SteerTip())
            // Long-press: steer the running reply instead of queueing (plan Q23).
            .contextMenu {
                if let onSteer {
                    Button("Steer the reply now", systemImage: "arrow.turn.up.right") { onSteer() }
                        .disabled(!canSend)
                }
            }
        }

        private var canSend: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
#endif
