#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// The memory graph (WP-52): a canvas with pinch to zoom, drag to pan and tap to open a node, and the timeline
    /// scrubber at the bottom.
    ///
    /// The layout is worked out once per graph by the model (`JourneyBoard`), so a gesture only changes the viewport and
    /// the canvas redraws marks it already has. Pinch and drag add up: each change applies only what moved since the
    /// last one, so a two-finger move that pans and zooms together does not fight itself. The same moves are also
    /// there as buttons (zoom in, zoom out, show everything), for people who cannot pinch, and every node is an
    /// accessibility element, so VoiceOver reads the graph as a list of nodes and opens one with a double tap.
    struct JourneyGraphView: View {
        let model: MemoryJourneyModel
        /// False while another screen is pushed on top of this one, so a message shows, and is read out, only once.
        var isActive = true

        @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
        @Environment(\.hermesReduceMotion) private var reduceMotionOverride
        @State private var lastDrag = CGSize.zero
        @State private var lastPinch = CGFloat(1)
        @GestureState private var isDragging = false
        @GestureState private var isPinching = false

        /// The marks get their names once the view is zoomed in this far, or when there are few of them.
        private static let labelZoom = 2.0
        private static let fewNodes = 12

        private var reduceMotion: Bool {
            HermesMotion.resolveReduceMotion(system: systemReduceMotion, override: reduceMotionOverride)
        }

        /// True when there are marks to draw, so the zoom buttons have something to zoom.
        private var showsMarks: Bool {
            model.phase == .loaded && !model.board.isEmpty
        }

        var body: some View {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack(alignment: .topTrailing) {
                        canvas(size: proxy.size)
                        if showsMarks {
                            JourneyZoomControls(model: model, size: proxy.size, animated: !reduceMotion)
                        }
                    }
                }
                .overlay { JourneyStatusView(model: model, shownCount: model.board.visibleCount) }
                .journeyNotices(model: model, isActive: isActive)
                JourneyScrubber(model: model)
            }
        }

        private func canvas(size: CGSize) -> some View {
            let board = model.board
            let input = JourneyCanvasInput(
                scene: board.scene, viewport: board.viewport, selectedID: model.selectedID,
                showsLabels: board.viewport.zoom >= Self.labelZoom || board.scene.nodes.count <= Self.fewNodes)
            return Canvas { context, canvasSize in
                JourneyCanvasRenderer.draw(input, in: &context, size: canvasSize)
            }
            .contentShape(Rectangle())
            .gesture(panGesture(size: size).exclusively(before: tapGesture(size: size)))
            .simultaneousGesture(pinchGesture(size: size))
            .onChange(of: isDragging) { _, active in
                if !active { lastDrag = .zero }
            }
            .onChange(of: isPinching) { _, active in
                if !active { lastPinch = 1 }
            }
            .accessibilityLabel("Memory graph")
            .accessibilityChildren { nodeElements(board) }
            .accessibilityIdentifier("memory.graph")
        }

        // MARK: Gestures

        private func tapGesture(size: CGSize) -> some Gesture {
            SpatialTapGesture()
                .onEnded { value in
                    model.tap(at: value.location, in: size)
                }
        }

        private func panGesture(size: CGSize) -> some Gesture {
            DragGesture(minimumDistance: 8)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { value in
                    let step = CGSize(
                        width: value.translation.width - lastDrag.width,
                        height: value.translation.height - lastDrag.height)
                    lastDrag = value.translation
                    model.pan(by: step, in: size)
                }
                .onEnded { _ in lastDrag = .zero }
        }

        private func pinchGesture(size: CGSize) -> some Gesture {
            MagnifyGesture()
                .updating($isPinching) { _, state, _ in state = true }
                .onChanged { value in
                    let factor = value.magnification / lastPinch
                    lastPinch = value.magnification
                    if factor.isFinite, factor > 0 {
                        model.zoom(by: Double(factor), around: value.startLocation, in: size)
                    }
                }
                .onEnded { _ in lastPinch = 1 }
        }

        // MARK: Accessibility

        /// One line for the graph as a whole and one button per node on screen, oldest first.
        private func nodeElements(_ board: JourneyBoard) -> some View {
            VStack {
                Text("\(board.visibleCount) of \(board.filteredCount) nodes shown")
                ForEach(board.scene.nodes) { mark in
                    Button(mark.label) { model.openNode(mark.id) }
                        .accessibilityLabel(board.graph.node(id: mark.id)?.spokenSummary ?? mark.label)
                        .accessibilityHint("Opens the details")
                        .accessibilityIdentifier("memory.node.\(mark.id)")
                }
            }
        }
    }

    /// Zoom in, zoom out and show everything, as buttons.
    struct JourneyZoomControls: View {
        let model: MemoryJourneyModel
        let size: CGSize
        let animated: Bool

        /// One press zooms by this much.
        private static let step = 1.6

        var body: some View {
            VStack(spacing: 8) {
                control("plus.magnifyingglass", label: "Zoom in", id: "memory.zoomIn") {
                    model.zoomStep(by: Self.step, in: size, animated: animated)
                }
                control("minus.magnifyingglass", label: "Zoom out", id: "memory.zoomOut") {
                    model.zoomStep(by: 1 / Self.step, in: size, animated: animated)
                }
                control(
                    "arrow.up.left.and.down.right.magnifyingglass", label: "Show everything", id: "memory.fit"
                ) {
                    model.fit(animated: animated)
                }
                .disabled(model.board.viewport == .fit)
            }
            .padding(12)
        }

        private func control(
            _ symbol: String, label: String, id: String, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: HermesMetrics.minTapTarget, height: HermesMetrics.minTapTarget)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: Circle())
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
        }
    }
#endif
