#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// Tools: the server's operating tools. Kanban appears only when the server runs the kanban plugin (WP-55).
    public struct ToolsHome: View {
        @State private var kanban: KanbanModel

        public init(connections: ConnectionsModel) {
            _kanban = State(initialValue: KanbanModel(connections: connections))
        }

        init(kanban: KanbanModel) {
            _kanban = State(initialValue: kanban)
        }

        public var body: some View {
            List {
                if kanban.isAvailable {
                    Section {
                        NavigationLink {
                            KanbanBoardScreen(model: kanban)
                        } label: {
                            Label("Kanban", systemImage: "rectangle.3.group")
                        }
                        .accessibilityIdentifier("tools.kanban")
                    }
                }
            }
            .navigationTitle("Tools")
            .task { await kanban.checkPresence() }
        }
    }

    #Preview("Tools, outer", traits: .fixedLayout(width: 466, height: 678)) {
        NavigationStack {
            ToolsHome(kanban: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Tools, inner portrait", traits: .fixedLayout(width: 626, height: 890)) {
        NavigationStack {
            ToolsHome(kanban: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Tools, inner landscape", traits: .fixedLayout(width: 890, height: 626)) {
        NavigationStack {
            ToolsHome(kanban: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }

    #Preview("Tools, half-fold", traits: .fixedLayout(width: 890, height: 313)) {
        NavigationStack {
            ToolsHome(kanban: .preview(board: KanbanSampleData.board, boards: KanbanSampleData.boards))
        }
    }
#endif
