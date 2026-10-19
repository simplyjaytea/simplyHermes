#if canImport(UIKit)
    import SwiftUI

    /// Offers an exported chat to the system share sheet (WP-40). The file holds the JSON the server sent.
    struct ExportedChatSheet: View {
        let chat: ExportedChat
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle)
                        .foregroundStyle(HermesColor.accent)
                        .accessibilityHidden(true)
                    Text(chat.url.lastPathComponent)
                        .font(HermesFont.body)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    ShareLink(item: chat.url) {
                        Label("Share chat", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(HermesButtonStyle(.tinted))
                    .accessibilityIdentifier("session.export.share")
                }
                .padding(24)
                .navigationTitle("Export chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
#endif
