#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The one overflow menu of a chat: Find in chat, Artifacts and Review changes. Artifacts shows only when the chat
    /// made images. Review changes shows only when the chat has a folder. Nothing shows when the menu would be empty.
    struct ChatMoreMenu: View {
        /// Whether the chat has any rows to search.
        let canFind: Bool
        /// Asked while this menu renders, so the scan of the transcript for images runs here and not in the screen.
        let hasArtifacts: () -> Bool
        let hasGitReview: Bool
        let onFind: () -> Void
        let onArtifacts: () -> Void
        let onGitReview: () -> Void

        var body: some View {
            let showsArtifacts = hasArtifacts()
            if canFind || showsArtifacts || hasGitReview {
                Menu {
                    if canFind {
                        Button(action: onFind) {
                            Label("Find in chat", systemImage: "magnifyingglass")
                        }
                        .accessibilityIdentifier("chat.find")
                    }
                    if showsArtifacts {
                        Button(action: onArtifacts) {
                            Label("Artifacts", systemImage: "photo.on.rectangle")
                        }
                        .accessibilityIdentifier("chat.artifacts")
                    }
                    if hasGitReview {
                        // Git review of the chat's folder, as the desktop app's right sidebar has it.
                        Button(action: onGitReview) {
                            Label("Review changes", systemImage: "arrow.triangle.branch")
                        }
                        .accessibilityIdentifier("chat.gitReview")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .cappedSymbolSize()
                        .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
                        .contentShape(Circle())
                }
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("More"))
                .accessibilityIdentifier("chat.more")
            }
        }
    }

    /// Slides ``RunningStopCapsule`` in and out above the composer as a reply starts and ends. It takes no room
    /// when idle.
    struct RunningStopSlot: View {
        let isRunning: Bool
        let onStop: () -> Void
        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride

        var body: some View {
            let reduceMotion = HermesMotion.resolveReduceMotion(
                system: systemReduceMotion, override: reduceMotionOverride)
            Group {
                if isRunning {
                    RunningStopCapsule(onStop: onStop)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(HermesMotion.animation(HermesMotion.snappy, reduceMotion: reduceMotion), value: isRunning)
        }
    }

    /// A glass capsule above the composer while Hermes is replying: a dot, the words, and a Stop button.
    struct RunningStopCapsule: View {
        let onStop: () -> Void
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            HStack(spacing: 8) {
                // A still dot. A repeating animation here would keep the app from going idle for the whole reply.
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text("Hermes is replying")
                    .font(HermesFont.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Stop", action: onStop)
                    .font(HermesFont.footnote.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: HermesMetrics.minTapTarget, minHeight: HermesMetrics.minTapTarget)
                    .contentShape(Rectangle())
                    .buttonStyle(.hermesPress)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: HermesMetrics.minTapTarget)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 12)
        }
    }

    /// The bottom info row of a chat with no server session behind it (a New chat or a demo chat): the status chip, which
    /// carries what the old top strip said, and the Hide keyboard button.
    struct PlaceholderInfoRow: View {
        let connection: StripConnection
        let serverName: String
        /// True when no server is saved, so the chip says "Set up a server" instead of "Can't reach".
        let hasNoServer: Bool

        var body: some View {
            HStack(spacing: 0) {
                StatusPill(pill: pill, serverName: serverName)
                    .padding(.horizontal, 12)
                Spacer(minLength: 0)
                HideKeyboardButton()
            }
            .frame(minHeight: 28)
        }

        /// The chip's state for the strip's connection. The strip and the pill come from the same rules.
        private var pill: PillState {
            switch connection {
            case .online: .connected
            case .reconnecting: .reconnecting
            case .offline: hasNoServer ? .noServer : .unreachable
            case .needsAttention: .needsAttention(.signIn)
            }
        }
    }
#endif
