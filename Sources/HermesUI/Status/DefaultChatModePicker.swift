#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings › Connection: the mode a new chat starts in. It changes no chat that already exists.
    struct DefaultChatModePicker: View {
        @Environment(\.hermesPalette) private var palette
        @State private var mode = ChatModeDefault.current

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Picker("New chats start as", selection: $mode) {
                    Text("Online").tag(ChatMode.online)
                    Text("Local").tag(ChatMode.local)
                }
                .onChange(of: mode) { _, new in ChatModeDefault.save(new, to: .standard) }
                .accessibilityIdentifier("settings.defaultMode")
                Text("Only new chats. A chat keeps its mode.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }
#endif
