#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Shows its content only while the software keyboard is down. It reads ``KeyboardWatcher`` here, so a keyboard
    /// change re-renders this small view and not the chat screen around it.
    struct KeyboardHidden<Content: View>: View {
        @ViewBuilder let content: () -> Content

        var body: some View {
            if !KeyboardWatcher.shared.isUp {
                content()
            }
        }
    }

    #if DEBUG
        /// The hidden status line a UI test reads when an outage assertion fails (WP-8). It is its own view because it
        /// reads the draft: inside the chat screen every keystroke would render the whole screen.
        struct ChatDebugStatus: View {
            let chat: LiveChatModel
            let model: ShellModel
            let sessionID: String

            var body: some View {
                Text(summary)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityIdentifier("uiTest.chatStatus")
            }

            /// The status, and what a send from the screen would use: the chat it is for, the chat the shell has
            /// selected, the draft, the waiting rows and the last send error.
            private var summary: String {
                let draft = model.drafts[sessionID, default: ""]
                let send = "screen=\(sessionID) selected=\(model.selectedSessionID ?? "none") draft=\(draft.count)"
                let outbox = "waitingRows=\(chat.outboxRows.count) sendError=\(chat.outboxError ?? "none")"
                return "\(chat.debugStatusSummary) \(send) \(outbox)"
            }
        }
    #endif
#endif
