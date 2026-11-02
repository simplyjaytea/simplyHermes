#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI

    /// Undo for chat delete, shared by every chat list (feature C). Server chats and local chats use the same queue,
    /// the same 5 s window and the same toast. The real delete runs when the window ends; the app leaving the
    /// foreground cancels every pending one.
    @MainActor @Observable
    public final class ChatDeletes {
        public static let shared = ChatDeletes()

        /// The delete the toast offers to undo.
        public private(set) var latest: PendingChatDelete?
        /// Chats no list may show: inside the Undo window, or being deleted.
        public private(set) var hiddenIDs: Set<String> = []
        /// Why the last delete failed. The chat is back in its list; the toast shows this until dismissed.
        public private(set) var errorText: String?

        @ObservationIgnored private let queue: ChatDeleteQueue
        @ObservationIgnored private var timer: Task<Void, Never>?

        init(queue: ChatDeleteQueue = ChatDeleteQueue()) {
            self.queue = queue
        }

        /// Hides a chat and starts its Undo window. `commit` runs the real delete when the window ends and returns how
        /// many waiting messages went with it.
        public func delete(
            id: String, title: String, waitingMessages: Int = 0, commit: @escaping ChatDeleteQueue.Commit
        ) {
            guard let item = queue.delete(id: id, title: title, waitingMessages: waitingMessages, commit: commit)
            else { return }
            errorText = nil
            sync()
            AccessibilityNotification.Announcement(item.announcement).post()
            schedule()
        }

        /// Undo on the toast: the newest pending chat comes back.
        public func undoLatest() {
            guard let latest else { return }
            queue.undo(latest.id)
            sync()
            schedule()
        }

        /// The app left the foreground: nothing pending is deleted.
        public func cancelAll() {
            queue.cancelAll()
            sync()
            schedule()
        }

        /// VoiceOver focus entered or left the toast.
        public func hold(_ held: Bool) {
            guard let latest else { return }
            queue.hold(latest.id, held)
            sync()
            schedule()
        }

        public func dismissError() {
            errorText = nil
        }

        private func sync() {
            latest = queue.latest
            hiddenIDs = queue.hiddenIDs
        }

        /// Sleeps until the next window ends, runs the due deletes, and repeats while any are waiting.
        private func schedule() {
            timer?.cancel()
            guard let deadline = queue.nextDeadline else { return }
            timer = Task { [weak self] in
                let wait = max(0, deadline.timeIntervalSinceNow)
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                guard !Task.isCancelled, let self else { return }
                await self.runDue()
            }
        }

        private func runDue() async {
            let outcomes = await queue.tick()
            sync()
            for case .restored(_, let title, let reason) in outcomes {
                errorText = "Couldn't delete “\(title)”: \(reason) It's back in the list."
                AccessibilityNotification.Announcement(errorText ?? "").post()
            }
            schedule()
        }
    }

    /// The Undo toast: "Chat deleted · Undo" for 5 s after a delete, or why a delete failed. It sits at the bottom of
    /// the shell, above the tab bar. VoiceOver focus on it holds the delete.
    public struct ChatDeleteToast: View {
        @Bindable private var deletes: ChatDeletes
        @Environment(\.hermesPalette) private var palette
        @AccessibilityFocusState private var isFocused: Bool

        public init(deletes: ChatDeletes = .shared) {
            self.deletes = deletes
        }

        public var body: some View {
            VStack {
                if let pending = deletes.latest {
                    toast(pending.message) {
                        Button("Undo") { deletes.undoLatest() }
                            .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                            .accessibilityHint("Brings the chat back")
                            .accessibilityIdentifier("chatDelete.undo")
                    }
                    .accessibilityIdentifier("chatDelete.toast")
                    .accessibilityFocused($isFocused)
                    .id(pending.id)
                } else if let error = deletes.errorText {
                    toast(error) {
                        Button("OK") { deletes.dismissError() }
                            .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                    }
                    .accessibilityIdentifier("chatDelete.error")
                }
            }
            .animation(.snappy, value: deletes.latest?.id)
            .onChange(of: isFocused) { _, focused in deletes.hold(focused) }
        }

        private func toast(_ text: String, @ViewBuilder action: () -> some View) -> some View {
            HStack(spacing: 12) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                action()
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
#endif
