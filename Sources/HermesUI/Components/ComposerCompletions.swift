#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI

    /// Looks up the completions of a composer token. The composer calls it with each token it completes.
    public typealias CompletionLookup = @Sendable (ComposerTrigger) async -> [CompletionItem]

    /// The completions of the word under the caret. A keystroke restarts the lookup, so only the newest one shows.
    @MainActor
    @Observable
    final class ComposerCompletions {
        /// The word that is completed, or nil when the caret is not in one.
        private(set) var token: ComposerToken?
        /// Completions for `token`, best match first.
        private(set) var items: [CompletionItem] = []
        @ObservationIgnored private var lookup: Task<Void, Never>?

        /// Looks up the completions for the word under the caret. Waits briefly first, so fast typing does not
        /// send a request per letter.
        func update(
            text: String, caret: Int, using fetch: @escaping CompletionLookup
        ) {
            let next = ComposerTokens.active(in: text, caret: caret)
            guard next != token else { return }
            token = next
            lookup?.cancel()
            guard let next else {
                items = []
                return
            }
            lookup = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let found = await fetch(next.trigger)
                guard !Task.isCancelled else { return }
                items = found
            }
        }

        /// Replaces the word with the picked completion. Returns the new text and caret, or nil when no word is
        /// active.
        func accept(_ item: CompletionItem, in text: String) -> (text: String, caret: Int)? {
            guard let token else { return nil }
            let sigil = Self.sigil(of: token.trigger)
            let replacement = item.text.hasPrefix(sigil) ? item.text : sigil + item.text
            lookup?.cancel()
            self.token = nil
            items = []
            return ComposerTokens.replacing(token, in: text, with: replacement)
        }

        private static func sigil(of trigger: ComposerTrigger) -> String {
            switch trigger {
            case .slash: "/"
            case .mention: "@"
            }
        }
    }

    /// The completion rows above the field, in glass (plan Q24). Tapping a row puts it into the message.
    struct CompletionPopover: View {
        let items: [CompletionItem]
        let onPick: (CompletionItem) -> Void

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(6).enumerated()), id: \.offset) { _, item in
                    Button {
                        onPick(item)
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.label)
                                .font(HermesFont.body.monospaced())
                                .foregroundStyle(HermesColor.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !item.meta.isEmpty {
                                Text(item.meta)
                                    .font(HermesFont.caption)
                                    .foregroundStyle(HermesColor.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: HermesMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item.label))
                }
            }
            .padding(.vertical, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("composer.completions")
        }
    }
#endif
