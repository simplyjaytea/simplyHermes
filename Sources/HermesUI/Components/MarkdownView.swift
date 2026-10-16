#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Chat text with block markdown: headings, lists, quotes, rules and code blocks with a Copy button. Inline
    /// markdown is handled by ``InlineMarkdown``.
    struct MarkdownView: View {
        let text: String
        /// Fades in new characters at the end of the last paragraph while the reply streams (plan Q47).
        var fadesNewText = false

        var body: some View {
            let blocks = MarkdownBlocks.parse(text)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    if fadesNewText, index == blocks.count - 1, case .paragraph(let value) = block {
                        Text(InlineMarkdown.attributed(value)).font(HermesFont.bubble)
                            .modifier(StreamingFade(text: value))
                    } else {
                        view(for: block)
                    }
                }
            }
        }

        @ViewBuilder
        private func view(for block: MarkdownBlock) -> some View {
            switch block {
            case .paragraph(let value):
                Text(InlineMarkdown.attributed(value)).font(HermesFont.bubble)
            case .heading(let level, let value):
                Text(InlineMarkdown.attributed(value))
                    .font(level <= 1 ? HermesFont.headline.weight(.bold) : HermesFont.headline)
                    .accessibilityAddTraits(.isHeader)
            case .code(let language, let value, _):
                CodeBlockView(language: language, code: value)
            case .list(let start, let items):
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(start.map { "\($0 + offset)." } ?? "•")
                                .font(HermesFont.bubble.monospacedDigit())
                                .foregroundStyle(HermesColor.secondaryText)
                            Text(InlineMarkdown.attributed(item)).font(HermesFont.bubble)
                        }
                    }
                }
            case .quote(let value):
                HStack(spacing: 8) {
                    Capsule().fill(HermesColor.separator).frame(width: 3)
                    Text(InlineMarkdown.attributed(value))
                        .font(HermesFont.bubble)
                        .foregroundStyle(HermesColor.secondaryText)
                }
            case .rule:
                Divider()
            }
        }
    }

    /// A code block in monospace that scrolls sideways, with the language and a Copy button.
    struct CodeBlockView: View {
        let language: String?
        let code: String
        @State private var copyCount = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language ?? "code")
                        .font(HermesFont.caption)
                        .foregroundStyle(HermesColor.secondaryText)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        copyCount += 1
                    } label: {
                        Label(
                            copyCount > 0 ? "Copied" : "Copy", systemImage: copyCount > 0 ? "checkmark" : "doc.on.doc"
                        )
                        .font(HermesFont.caption.weight(.semibold))
                        .frame(minHeight: HermesMetrics.minTapTarget - 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Copy code"))
                }
                .padding(.horizontal, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(Self.highlighted(code, language: language))
                        .font(HermesFont.code)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .background(
                HermesColor.fill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }

        /// The code with system colors for keywords, strings, comments and numbers. Closed blocks only change when
        /// the text does, so streaming a long block re-scans it on each update; blocks are short in practice.
        static func highlighted(_ code: String, language: String?) -> AttributedString {
            var result = AttributedString()
            for token in SyntaxHighlighter.tokens(for: code, language: language) {
                var piece = AttributedString(token.text)
                switch token.kind {
                case .plain: break
                case .keyword: piece.foregroundColor = .purple
                case .string: piece.foregroundColor = .red
                case .comment: piece.foregroundColor = .secondary
                case .number: piece.foregroundColor = .teal
                }
                result.append(piece)
            }
            return result
        }
    }
#endif
