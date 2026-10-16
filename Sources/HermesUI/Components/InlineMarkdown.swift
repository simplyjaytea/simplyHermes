#if canImport(UIKit)
    import Foundation

    /// Inline markdown for chat text: bold, italics, code spans and links, with line breaks kept. Block syntax
    /// (headings, lists, fenced code) shows as typed until the block renderer arrives.
    enum InlineMarkdown {
        static func attributed(_ text: String) -> AttributedString {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
            return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        }
    }
#endif
