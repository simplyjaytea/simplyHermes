#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Settings › Connection: the mode a new chat starts in. It changes no chat that already exists.
    struct DefaultChatModePicker: View {
        @State private var mode = ChatModeDefault.current

        var body: some View {
            Picker("New chats start as", selection: $mode) {
                Text("Online").tag(ChatMode.online)
                Text("Local").tag(ChatMode.local)
            }
            .onChange(of: mode) { _, new in ChatModeDefault.save(new, to: .standard) }
            .accessibilityIdentifier("settings.defaultMode")
        }
    }
#endif
