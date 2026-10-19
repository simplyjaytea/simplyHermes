#if canImport(UIKit)
    import HermesKit
    import SwiftUI
    import UIKit

    // The two screens of the memory journey (WP-52). Each can be the first screen and can push the other, so the outer
    // layout (list first, Graph button) and the inner layouts (graph first, List button) share them.

    /// The node list with the filter chips and, on the outer screen, a Graph button that pushes the graph.
    struct JourneyListScreen: View {
        let model: MemoryJourneyModel
        /// True when this list is the first screen and the graph is one tap away. False when the graph pushed it.
        let showsGraphButton: Bool
        @State private var showsGraph = false

        var body: some View {
            JourneyListView(model: model)
                .journeyNotices(model: model, isActive: !showsGraph)
                .navigationTitle(showsGraphButton ? "Memory" : "Nodes")
                .toolbar { toolbar }
                .navigationDestination(isPresented: $showsGraph) {
                    JourneyGraphScreen(model: model, showsListButton: false)
                }
                .journeyNodeSheet(model: model, isActive: !showsGraph)
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.isRefreshing {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().accessibilityLabel("Refreshing")
                }
            }
            if showsGraphButton {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsGraph = true
                    } label: {
                        Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(model.board.isEmpty)
                    .accessibilityIdentifier("memory.graphButton")
                }
            }
        }
    }

    /// The graph with the filter chips on top. On the inner screens it is the first screen and has a List button; on
    /// the outer screen the list pushed it.
    struct JourneyGraphScreen: View {
        let model: MemoryJourneyModel
        /// True when this graph is the first screen and the list is one tap away. False when the list pushed it.
        let showsListButton: Bool
        @State private var showsList = false
        @State private var showsLayoutCodeSheet = false

        var body: some View {
            VStack(spacing: 0) {
                if !model.board.isEmpty { JourneyFilterBar(model: model) }
                JourneyGraphView(model: model, isActive: !showsList)
            }
            .navigationTitle(showsListButton ? "Memory" : "Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showsLayoutCodeSheet) { LayoutCodeSheet(model: model) }
            .navigationDestination(isPresented: $showsList) {
                JourneyListScreen(model: model, showsGraphButton: false)
            }
            .journeyNodeSheet(model: model, isActive: !showsList)
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            if model.isRefreshing {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().accessibilityLabel("Refreshing")
                }
            }
            if showsListButton {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsList = true
                    } label: {
                        Label("List", systemImage: "list.bullet")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("memory.listButton")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyLayoutCode()
                } label: {
                    Label("Copy layout code", systemImage: "square.and.arrow.up")
                }
                .disabled(model.board.isEmpty)
                .accessibilityHint("Copies a code that restores this view on another device")
                .accessibilityIdentifier("memory.copyCode")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Apply layout code\u{2026}", systemImage: "square.and.pencil") {
                        showsLayoutCodeSheet = true
                    }
                    .accessibilityIdentifier("memory.applyCode")
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .accessibilityIdentifier("memory.refresh")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("memory.layoutMenu")
            }
        }

        private func copyLayoutCode() {
            UIPasteboard.general.string = model.layoutCode
            model.post("Layout code copied.")
        }
    }

    extension View {
        /// Presents the sheet of the open node while `isActive`. Only the screen on top passes `isActive`, so a node
        /// opens one sheet and not one for every screen of the stack.
        func journeyNodeSheet(model: MemoryJourneyModel, isActive: Bool) -> some View {
            sheet(
                item: Binding<NodeEditorModel?>(
                    get: { isActive ? model.editor : nil },
                    set: { if $0 == nil { model.closeEditor() } }
                )
            ) { editor in
                NodeSheet(editor: editor)
            }
        }
    }
#endif
