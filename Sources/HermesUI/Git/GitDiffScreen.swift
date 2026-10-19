#if canImport(SwiftUI)
    import HermesKit
    import SwiftUI

    /// How the diff lays out: side by side when the screen is wide enough, stacked otherwise, or forced either way.
    enum GitDiffLayout: String, CaseIterable, Identifiable {
        case automatic
        case stacked
        case sideBySide

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Auto"
            case .stacked: "Stacked"
            case .sideBySide: "Side by side"
            }
        }
    }

    /// The diff of one file in the review's scope. Wide screens, such as a Duo's inner display in landscape, show the old
    /// and new sides next to each other.
    struct GitDiffScreen: View {
        let model: GitReviewModel
        let file: GitReviewFile

        @State private var hunks: [GitDiffHunk] = []
        @State private var loading = true
        @State private var layout: GitDiffLayout = .automatic

        /// The width at which two columns fit.
        private let twoColumnWidth: CGFloat = 700

        var body: some View {
            GeometryReader { proxy in
                let sideBySide = layout == .sideBySide || (layout == .automatic && proxy.size.width >= twoColumnWidth)
                let column = max(proxy.size.width / 2, 320)
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                            hunkHeader(hunk.header)
                            if sideBySide {
                                ForEach(Array(GitDiffParser.rows(in: hunk).enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 0) {
                                        cell(row.old, old: true, column: column)
                                        cell(row.new, old: false, column: column)
                                    }
                                }
                            } else {
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    stackedLine(line)
                                }
                            }
                        }
                    }
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            .overlay {
                if !loading && hunks.isEmpty {
                    ContentUnavailableView("No text changes", systemImage: "doc.text")
                }
            }
            .navigationTitle(file.path)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Layout", selection: $layout) {
                        ForEach(GitDiffLayout.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
            }
            .task { await load() }
        }

        private func load() async {
            loading = true
            let diff = await model.diff(for: file) ?? ""
            hunks = GitDiffParser.hunks(in: diff)
            loading = false
        }

        private func hunkHeader(_ header: String) -> some View {
            Text(header)
                .font(HermesFont.code)
                .foregroundStyle(HermesColor.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }

        private func stackedLine(_ line: GitDiffLine) -> some View {
            HStack(alignment: .top, spacing: 8) {
                gutter(line.oldNumber)
                gutter(line.newNumber)
                Text(Self.marker(for: line.kind))
                Text(line.text)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(HermesFont.code)
            .padding(.horizontal, 8)
            .background(Self.background(for: line.kind))
        }

        /// One side of a side-by-side row. `old` picks which line number the cell shows.
        private func cell(_ line: GitDiffLine?, old: Bool, column: CGFloat) -> some View {
            let number = old ? line?.oldNumber : line?.newNumber
            return HStack(alignment: .top, spacing: 8) {
                gutter(number)
                Text(line.map { Self.marker(for: $0.kind) } ?? "")
                Text(line?.text ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(HermesFont.code)
            .frame(width: column, alignment: .leading)
            .padding(.horizontal, 8)
            .background(Self.background(for: line?.kind))
        }

        private func gutter(_ number: Int?) -> some View {
            Text(number.map(String.init) ?? "")
                .foregroundStyle(HermesColor.secondaryText)
                .frame(width: 40, alignment: .trailing)
        }

        private static func marker(for kind: GitDiffLine.Kind) -> String {
            switch kind {
            case .added: "+"
            case .removed: "-"
            case .context: " "
            }
        }

        private static func background(for kind: GitDiffLine.Kind?) -> Color {
            switch kind {
            case .added?: Color.green.opacity(0.18)
            case .removed?: Color.red.opacity(0.16)
            case .context?: Color.clear
            case nil: Color.secondary.opacity(0.06)
            }
        }
    }
#endif
