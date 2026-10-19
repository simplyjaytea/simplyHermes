#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Quick Entry: a text box and a Send button, opened from the Action button, Control Center or Siri.
    ///
    /// The sheet decides nothing about where the message goes. ``QuickEntryPolicy`` does, so changing what Quick Entry
    /// does is one edit there.
    public struct QuickEntrySheet: View {
        @Bindable private var coordinator: QuickEntryCoordinator
        private let hasServer: Bool
        private let onSend: (String, OutboundTarget) -> Void

        @FocusState private var isFocused: Bool
        @State private var sendCount = 0

        /// - Parameters:
        ///   - hasServer: false while no server is saved. The sheet then explains why it cannot send.
        ///   - onSend: receives the text and where it goes. The sheet clears itself afterwards.
        public init(
            coordinator: QuickEntryCoordinator, hasServer: Bool = true,
            onSend: @escaping (String, OutboundTarget) -> Void
        ) {
            self.coordinator = coordinator
            self.hasServer = hasServer
            self.onSend = onSend
        }

        private var destination: QuickEntryDestination {
            coordinator.startsNewChat
                ? QuickEntryPolicy.newChat : QuickEntryPolicy.destination(lastChat: coordinator.lastChat)
        }

        private var canSend: Bool {
            hasServer && !coordinator.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HermesSheetHeader("Ask Hermes") { coordinator.isPresented = false }
                    TextField("Message Hermes", text: $coordinator.text, axis: .vertical)
                        .focused($isFocused)
                        .font(HermesFont.body)
                        .lineLimit(3...8)
                        .padding(14)
                        .background(
                            HermesColor.fill,
                            in: RoundedRectangle(cornerRadius: HermesMetrics.innerRadius, style: .continuous)
                        )
                        .accessibilityIdentifier("quickEntry.field")
                    destinationNote
                    Button(action: send) {
                        Label("Send", systemImage: "arrow.up")
                    }
                    .buttonStyle(HermesButtonStyle(.primary))
                    .disabled(!canSend)
                    .accessibilityIdentifier("quickEntry.send")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(HermesColor.background)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .hermesFeedback(.send, trigger: sendCount)
            .task {
                // The sheet is still sliding in; focusing at once can be ignored.
                try? await Task.sleep(for: .milliseconds(250))
                isFocused = true
            }
        }

        private var destinationNote: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(hasServer ? destination.label : "Add a server in simplyHermes first.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                    .accessibilityIdentifier("quickEntry.destination")
                if hasServer, coordinator.lastChat != nil {
                    Toggle("Start a new chat instead", isOn: $coordinator.startsNewChat)
                        .font(HermesFont.subheadline)
                        .accessibilityIdentifier("quickEntry.newChat")
                }
            }
        }

        private func send() {
            guard canSend else { return }
            sendCount += 1
            onSend(coordinator.text, destination.target)
            coordinator.finish()
        }
    }
#endif
