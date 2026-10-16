#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Chat text with block markdown: headings, lists, quotes, rules and code blocks with a Copy button. Inline
    /// markdown is handled by ``InlineMarkdown``.
    struct MarkdownView: View {
        let text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                    view(for: block)
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
                    Text(verbatim: code)
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
    }
#endif
