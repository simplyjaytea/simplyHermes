#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    /// The text view behind the composer. Up and Down go to `onRecall` first, which steps through sent messages.
    /// Returning false leaves the key to the text view, so the caret still moves between lines.
    final class ComposerUITextView: UITextView {
        var onRecall: ((ComposerRecallDirection) -> Bool)?

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let key = presses.first?.key?.keyCode
            var handled = false
            if key == .keyboardUpArrow {
                handled = onRecall?(.older) ?? false
            } else if key == .keyboardDownArrow {
                handled = onRecall?(.newer) ?? false
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }
    }

    /// The composer's text view. It is UIKit so that mention words can be blue and the caret can move after a
    /// completion, which a SwiftUI text field cannot do. It grows with its text up to six lines.
    struct ComposerTextView: UIViewRepresentable {
        /// Most lines the field grows to before it scrolls.
        private static let maxLines: CGFloat = 6
        private static let verticalInset: CGFloat = 11

        @Binding var text: String
        /// The caret, or the selected range, in UTF-16 units.
        @Binding var selection: NSRange
        var onRecall: ((ComposerRecallDirection) -> Bool)?

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeUIView(context: Context) -> ComposerUITextView {
            let view = ComposerUITextView()
            view.delegate = context.coordinator
            view.backgroundColor = .clear
            view.font = UIFont.preferredFont(forTextStyle: .body)
            view.adjustsFontForContentSizeCategory = true
            view.textColor = .label
            view.textContainerInset = UIEdgeInsets(
                top: Self.verticalInset, left: 0, bottom: Self.verticalInset, right: 0)
            view.textContainer.lineFragmentPadding = 0
            view.accessibilityIdentifier = "composer.field"
            view.accessibilityLabel = String(localized: "Message")
            return view
        }

        func updateUIView(_ view: ComposerUITextView, context: Context) {
            context.coordinator.parent = self
            view.onRecall = onRecall
            // Only a change from outside, such as a cleared draft or a picked completion, rewrites the view.
            if view.text != text {
                view.text = text
            }
            if NSMaxRange(selection) <= view.text.utf16.count, view.selectedRange != selection {
                view.selectedRange = selection
            }
            context.coordinator.highlightMentions(in: view)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerUITextView, context: Context) -> CGSize? {
            guard let width = proposal.width, width > 0 else { return nil }
            let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let lineHeight = ceil((uiView.font?.lineHeight ?? 20))
            let tallest = lineHeight * Self.maxLines + 2 * Self.verticalInset
            return CGSize(width: width, height: min(fitting.height, tallest))
        }

        @MainActor
        final class Coordinator: NSObject, UITextViewDelegate {
            var parent: ComposerTextView

            init(_ parent: ComposerTextView) {
                self.parent = parent
            }

            func textViewDidChange(_ textView: UITextView) {
                parent.text = textView.text
                parent.selection = textView.selectedRange
                highlightMentions(in: textView)
            }

            func textViewDidChangeSelection(_ textView: UITextView) {
                parent.selection = textView.selectedRange
            }

            /// Colors the mention words blue and the rest of the text in the label color. It changes attributes only,
            /// so the text and the caret stay where they are.
            func highlightMentions(in textView: UITextView) {
                let storage = textView.textStorage
                storage.beginEditing()
                storage.addAttribute(
                    .foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: storage.length))
                for range in ComposerTokens.mentionRanges(in: textView.text) {
                    storage.addAttribute(
                        .foregroundColor, value: UIColor(HermesColor.accent),
                        range: NSRange(location: range.lowerBound, length: range.count))
                }
                storage.endEditing()
            }
        }
    }
#endif
