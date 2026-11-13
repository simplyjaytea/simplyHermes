#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    extension Notification.Name {
        /// Asks a chat's composer to take the keyboard, for example after "Quote in reply" filled the draft. The
        /// chat is named by ``hermesComposerFocusKey`` in `userInfo`; only the composer with that key answers.
        static let hermesComposerFocusRequest = Notification.Name("HermesComposerFocusRequest")
    }

    /// The `userInfo` key of ``Notification/Name/hermesComposerFocusRequest``.
    let hermesComposerFocusKey = "chat"

    extension EnvironmentValues {
        /// The chat a screen shows, so its message menu and its composer agree on which composer Quote focuses. With
        /// two chat windows open, each has its own key.
        @Entry var hermesChatFocusKey: String? = nil  // swiftlint:disable:this redundant_optional_initialization
    }

    extension View {
        /// The long-press menu of a chat message: Copy, Share, Quote in reply and Select text, then the row's own
        /// items (`extra`), such as Edit, Regenerate or Branch. The same actions are VoiceOver custom actions.
        ///
        /// - Parameters:
        ///   - text: The message as written (Markdown source), which Copy, Share and Quote use.
        ///   - isEnabled: False while the message is still streaming in.
        ///   - onQuote: Puts the quote of `text` into the chat's draft. It never sends.
        func messageActions<Extra: View>(
            text: String,
            isEnabled: Bool = true,
            onQuote: @escaping (String) -> Void,
            @ViewBuilder extra: () -> Extra
        ) -> some View {
            modifier(MessageActionsModifier(text: text, isEnabled: isEnabled, onQuote: onQuote, extra: extra()))
        }

        /// ``messageActions(text:isEnabled:onQuote:extra:)`` with no row-specific items.
        func messageActions(text: String, isEnabled: Bool = true, onQuote: @escaping (String) -> Void) -> some View {
            messageActions(text: text, isEnabled: isEnabled, onQuote: onQuote) { EmptyView() }
        }
    }

    private struct MessageActionsModifier<Extra: View>: ViewModifier {
        let text: String
        let isEnabled: Bool
        let onQuote: (String) -> Void
        let extra: Extra

        @State private var isSelectingText = false
        @Environment(\.hermesChatFocusKey) private var focusKey
        @State private var feedbackCount = 0

        func body(content: Content) -> some View {
            content
                .contextMenu {
                    Group {
                        Button("Copy", systemImage: "doc.on.doc", action: copy)
                            .accessibilityIdentifier("message.action.copy")
                        ShareLink(item: text) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("message.action.share")
                        Button("Quote in reply", systemImage: "text.quote", action: quote)
                            .accessibilityIdentifier("message.action.quote")
                        Button("Select text", systemImage: "selection.pin.in.out", action: selectText)
                            .accessibilityIdentifier("message.action.select")
                    }
                    .disabled(!isEnabled)
                    Divider()
                    extra
                }
                .accessibilityAction(named: Text("Copy"), copy)
                .accessibilityAction(named: Text("Quote in reply"), quote)
                .accessibilityAction(named: Text("Select text"), selectText)
                .sensoryFeedback(.success, trigger: feedbackCount)
                .sheet(isPresented: $isSelectingText) {
                    SelectTextSheet(text: text)
                }
        }

        private func copy() {
            guard isEnabled else { return }
            UIPasteboard.general.string = text
            feedbackCount += 1
        }

        private func quote() {
            guard isEnabled else { return }
            onQuote(text)
            feedbackCount += 1
            NotificationCenter.default.post(
                name: .hermesComposerFocusRequest, object: nil,
                userInfo: focusKey.map { [hermesComposerFocusKey: $0] })
        }

        private func selectText() {
            guard isEnabled else { return }
            isSelectingText = true
        }
    }

    /// The whole message in a sheet where part of it can be selected and copied. Long-press in the transcript opens
    /// the message menu, so this is where a partial copy happens.
    struct SelectTextSheet: View {
        let text: String
        @Environment(\.dismiss) private var dismiss
        @Environment(\.hermesPalette) private var palette

        var body: some View {
            NavigationStack {
                ScrollView {
                    Text(text)
                        .font(HermesFont.body)
                        .foregroundStyle(palette.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityIdentifier("message.selectText.body")
                }
                .background(palette.background)
                .navigationTitle("Select text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("message.selectText.done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
#endif
