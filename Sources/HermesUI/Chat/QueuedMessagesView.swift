#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Messages waiting for Hermes, as dimmed bubbles above the composer (plan Q23). Tap one to edit it, use the
    /// menu to move or remove it, and pause the whole queue from the header.
    struct QueuedMessagesView: View {
        @Bindable var chat: LiveChatModel
        @State private var editing: MessageQueue.Entry?
        @State private var editText = ""

        var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Text(chat.queue.isPaused ? "Queue paused" : "Waiting for Hermes")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                    Spacer()
                    Button(chat.queue.isPaused ? "Resume" : "Pause") {
                        chat.setQueuePaused(!chat.queue.isPaused)
                    }
                    .font(HermesFont.caption.weight(.semibold))
                    .accessibilityIdentifier("queue.pause")
                }
                ForEach(Array(chat.queue.entries.enumerated()), id: \.element.id) { index, entry in
                    Text(entry.text)
                        .font(HermesFont.bubble)
                        .foregroundStyle(HermesColor.onAccent)
                        .padding(.horizontal, HermesMetrics.bubbleHorizontalPadding)
                        .padding(.vertical, HermesMetrics.bubbleVerticalPadding)
                        .background(
                            HermesColor.outgoingBubble.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: HermesMetrics.bubbleRadius, style: .continuous)
                        )
                        .bubbleRow(.trailing)
                        .onTapGesture {
                            editText = entry.text
                            editing = entry
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                editText = entry.text
                                editing = entry
                            }
                            if index > 0 {
                                Button("Move up", systemImage: "arrow.up") { chat.moveQueued(entry.id, to: index - 1) }
                            }
                            if index < chat.queue.entries.count - 1 {
                                Button("Move down", systemImage: "arrow.down") {
                                    chat.moveQueued(entry.id, to: index + 1)
                                }
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) { chat.removeQueued(entry.id) }
                        }
                        .accessibilityLabel(Text("Queued message: \(entry.text)"))
                        .accessibilityHint(Text("Tap to edit"))
                        .accessibilityIdentifier("queued.\(entry.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .alert(
                "Edit queued message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
            ) {
                TextField("Message", text: $editText)
                Button("Save") {
                    if let editing { chat.editQueued(editing.id, to: editText) }
                    editing = nil
                }
                Button("Cancel", role: .cancel) { editing = nil }
            } message: {
                Text("Leave it empty to remove the message.")
            }
        }
    }
#endif
