#if canImport(UIKit)
    import SwiftUI

    /// Every design-system component on one page. Used for previews, snapshot tests and JT's review in the app.
    public struct ComponentGallery: View {
        public init() {}

        public var body: some View {
            VStack(alignment: .leading, spacing: 28) {
                GallerySection("Chat") { ChatSamples() }
                GallerySection("Buttons") { ButtonSamples() }
                GallerySection("Chips") { ChipSamples() }
                GallerySection("Cards and sheets") { CardSamples() }
                GallerySection("Status") { StatusSamples() }
                GallerySection("Composer") { ComposerSample() }
                GallerySection("Type") { TypeSamples() }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesColor.background)
        }
    }

    private struct GallerySection<Content: View>: View {
        let title: String
        let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(HermesFont.footnote.weight(.semibold))
                    .foregroundStyle(HermesColor.secondaryText)
                    .textCase(.uppercase)
                content
            }
        }
    }

    private struct ChatSamples: View {
        var body: some View {
            VStack(spacing: HermesMetrics.bubbleSpacing) {
                MessageBubble(role: .user, text: "Why did last night's backup cron fail? Fix it if you can.")
                MessageBubble(role: .assistant, text: "Checking the cron log first.")
                ToolOutputBubble(
                    command: "grep backup /var/log/syslog",
                    output: "rsync: connection unexpectedly closed (code 255)",
                    duration: "0.4 s"
                )
                MessageBubble(
                    role: .assistant,
                    text: "The NAS rejected the SSH key after its update. I can re-add the key and rerun the job."
                )
                ApprovalBubble(command: "ssh-copy-id backup@nas.local", onDeny: {}, onApprove: {})
                StreamingText(text: "Key added. Rerunning the backup", isStreaming: true)
                TypingIndicator()
            }
        }
    }

    private struct ButtonSamples: View {
        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Approve") {}.buttonStyle(HermesButtonStyle(.primary))
                    Button("Tinted") {}.buttonStyle(HermesButtonStyle(.tinted))
                }
                HStack(spacing: 8) {
                    Button("Delete bot") {}.buttonStyle(HermesButtonStyle(.destructive))
                    Button("Disabled") {}.buttonStyle(HermesButtonStyle(.primary)).disabled(true)
                }
            }
        }
    }

    private struct ChipSamples: View {
        var body: some View {
            HStack(spacing: 8) {
                HermesChip("Hermes 4", systemImage: "cpu", isSelected: true) {}
                HermesChip("Terminal", systemImage: "terminal") {}
                HermesChip("Voice", systemImage: "waveform") {}
            }
        }
    }

    private struct CardSamples: View {
        var body: some View {
            VStack(spacing: 12) {
                HermesCard {
                    Text("Nightly backup")
                        .font(HermesFont.headline)
                    Text("Every day at 02:00 on home-server")
                        .font(HermesFont.subheadline)
                        .foregroundStyle(HermesColor.secondaryText)
                }
                HermesCard {
                    HermesSheetHeader("New bot") {}
                    Text("Sheets open at half height and pull up to full height.")
                        .font(HermesFont.subheadline)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            }
            .padding(12)
            .background(
                HermesColor.groupedBackground,
                in: RoundedRectangle(cornerRadius: HermesMetrics.cardRadius, style: .continuous)
            )
        }
    }

    private struct StatusSamples: View {
        var body: some View {
            VStack(spacing: 8) {
                StatusStrip(connection: .connected, serverName: "home-server", runningTurn: "Running · 0:42") {}
                StatusStrip(connection: .reconnecting, serverName: "home-server")
                StatusStrip(connection: .offline, serverName: "office-mac")
            }
        }
    }

    private struct ComposerSample: View {
        @State private var draft = "Rerun the backup now"

        var body: some View {
            Composer(text: $draft) {}
        }
    }

    private struct TypeSamples: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Headline").font(HermesFont.headline)
                Text("Body text for messages and settings.").font(HermesFont.body)
                Text("Footnote for timestamps and hints.")
                    .font(HermesFont.footnote)
                    .foregroundStyle(HermesColor.secondaryText)
                Text(verbatim: "ssh-copy-id backup@nas.local").font(HermesFont.code)
            }
        }
    }

    #Preview("Outer", traits: .fixedLayout(width: 466, height: 678)) {
        ScrollView { ComponentGallery() }
    }

    #Preview("Inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        ScrollView { ComponentGallery() }
    }

    #Preview("Inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        ScrollView { ComponentGallery() }
    }

    #Preview("Half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        ScrollView { ComponentGallery() }
    }

    #Preview("Outer, dark", traits: .fixedLayout(width: 466, height: 678)) {
        ScrollView { ComponentGallery() }
            .preferredColorScheme(.dark)
    }
#endif
