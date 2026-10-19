#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// A short message over the content of the memory screen. It goes away on its own.
    public struct JourneyNotice: Sendable, Equatable, Identifiable {
        /// Grows with every notice, so a repeated text still counts as new.
        public var id: Int
        /// The words.
        public var text: String
        /// True for a failure.
        public var isError: Bool
    }

    /// Everything the memory screen keeps (WP-52): the loaded graph, the view settings, the open node and the messages.
    ///
    /// The views only forward touches to the model and draw what it holds. The rules that need no UI live in HermesKit
    /// and have Linux tests: `JourneyBoard` (filter, scrub, zoom, pan, taps, layout codes), `JourneyErrorText` and the
    /// words of `JourneyNode`. What stays here is the order of events. Loading follows these rules:
    /// - A load runs once at a time; asking again while one runs joins it.
    /// - A load for a server or profile the screen has left is dropped when it finishes.
    /// - The first load shows ``Phase/loading``. Later loads keep the list on screen and set ``isRefreshing``.
    /// - A failed later load keeps the old graph and posts a ``notice``; a failed first load shows ``Phase/failed(_:)``.
    @MainActor
    @Observable
    public final class MemoryJourneyModel {
        /// What the screen shows.
        public enum Phase: Sendable, Equatable {
            /// No server is selected.
            case notConnected
            /// The first load runs.
            case loading
            /// A graph is on screen. It may have no nodes.
            case loaded
            /// The first load failed. The text is the reason.
            case failed(String)
        }

        /// What the screen shows.
        public private(set) var phase: Phase = .notConnected
        /// The graph and the view settings.
        public private(set) var board = JourneyBoard.empty
        /// True while a load runs and the screen already has a graph.
        public private(set) var isRefreshing = false
        /// The name of the server the graph comes from.
        public private(set) var serverName: String?
        /// The message over the content, if there is one.
        public private(set) var notice: JourneyNotice?
        /// The node sheet, while a node is open.
        public private(set) var editor: NodeEditorModel?

        @ObservationIgnored private var source: JourneySource?
        @ObservationIgnored private var generation = 0
        @ObservationIgnored private var loadTask: Task<Void, Never>?
        @ObservationIgnored private var viewportTask: Task<Void, Never>?
        @ObservationIgnored private var knownProfile: String?
        @ObservationIgnored private var noticeCount = 0
        @ObservationIgnored private let pause: @Sendable (Duration) async throws -> Void

        /// The distance in points within which a touch counts as a hit on a node.
        public static let tapTolerance = 24.0
        /// How long a switch of profile settles before the graph is loaded again.
        public static let profileSettle = Duration.milliseconds(300)

        /// Creates an empty model. `pause` waits for a duration; tests pass one that does not really wait.
        public init(pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
            self.pause = pause
        }

        /// A model that already holds a graph, for previews, snapshots and tests: no server call is needed to show
        /// it, and opening a node reads from the sample backend.
        public static func sample(
            graph: JourneyGraph = JourneySample.graph, source: JourneySource = .sample()
        ) -> MemoryJourneyModel {
            let model = MemoryJourneyModel()
            model.source = source
            model.serverName = source.name
            model.board = JourneyBoard(graph: graph)
            model.phase = .loaded
            return model
        }

        // MARK: - Reading

        /// The code that restores the current view on another device.
        public var layoutCode: String { board.layoutCode }

        /// True when a graph loaded and it has no nodes.
        public var isEmptyGraph: Bool { phase == .loaded && board.isEmpty }

        /// The id of the node whose sheet is open.
        public var selectedID: String? { editor?.node.id }

        // MARK: - Connecting and loading

        /// Points the screen at `newSource` (nil for no server) and loads it. The same server only loads again. A
        /// different server throws away the old graph first, so one server's nodes never show under another's name.
        public func attach(_ newSource: JourneySource?) async {
            if let newSource, newSource.id == source?.id {
                source = newSource
                await refresh()
                return
            }
            discardGraph()
            source = newSource
            serverName = newSource?.name
            guard let newSource else {
                phase = .notConnected
                return
            }
            phase = .loading
            let mine = generation
            let profile = await newSource.currentProfile()
            guard mine == generation else { return }
            knownProfile = profile
            await refresh()
        }

        /// Loads the graph again. A load that already runs is joined instead of started twice.
        public func refresh() async {
            guard let task = startLoad() else { return }
            await task.value
        }

        /// Notices a switch of profile on the server and loads that profile's graph. ``watchProfile(every:)`` calls it
        /// on a timer.
        public func checkProfile() async {
            guard let source else { return }
            let profile = await source.currentProfile()
            guard source.id == self.source?.id, profile != knownProfile else { return }
            knownProfile = profile
            // The REST client takes the new profile in its own task; give it a moment before the next call.
            do { try await pause(Self.profileSettle) } catch { return }
            guard source.id == self.source?.id else { return }
            discardGraph()
            phase = .loading
            await refresh()
        }

        /// Checks for a switch of profile every `interval` until the calling task is cancelled.
        public func watchProfile(every interval: Duration = .seconds(3)) async {
            while !Task.isCancelled {
                do { try await pause(interval) } catch { return }
                guard !Task.isCancelled else { return }
                await checkProfile()
            }
        }

        private func startLoad() -> Task<Void, Never>? {
            guard let source else {
                phase = .notConnected
                return nil
            }
            if let loadTask { return loadTask }
            let mine = generation
            if phase == .loaded { isRefreshing = true } else { phase = .loading }
            let task = Task { [weak self] in
                let result: Result<JourneyGraph, any Error>
                do { result = .success(try await source.backend.learningGraph()) } catch { result = .failure(error) }
                self?.finishLoad(result, generation: mine)
            }
            loadTask = task
            return task
        }

        private func finishLoad(_ result: Result<JourneyGraph, any Error>, generation mine: Int) {
            guard mine == generation else { return }
            loadTask = nil
            isRefreshing = false
            switch result {
            case .success(let graph):
                board.replaceGraph(graph)
                phase = .loaded
            case .failure(let error):
                let text = JourneyErrorText.message(for: error, doing: .load)
                if phase == .loaded { post(text, isError: true) } else { phase = .failed(text) }
            }
        }

        /// Forgets the graph and everything tied to it. Loads that still run are dropped when they finish.
        private func discardGraph() {
            generation += 1
            loadTask?.cancel()
            loadTask = nil
            viewportTask?.cancel()
            viewportTask = nil
            board = .empty
            isRefreshing = false
            notice = nil
            editor = nil
        }

        // MARK: - View settings

        /// Chooses the All, Used or Learned chip.
        public func setFilter(_ filter: JourneyFilter) {
            board.setFilter(filter)
        }

        /// Moves the timeline scrubber to `position`, 0 to 1.
        public func setScrub(_ position: Double) {
            board.setScrub(position)
        }

        /// Zooms by `factor` around a point of the graph view, like a pinch. It stops a running move of the view.
        public func zoom(by factor: Double, around anchor: CGPoint, in size: CGSize) {
            stopGlide()
            board.zoom(by: factor, around: anchor, in: size)
        }

        /// Moves the view by a drag of `translation` points. It stops a running move of the view.
        public func pan(by translation: CGSize, in size: CGSize) {
            stopGlide()
            board.pan(by: translation, in: size)
        }

        /// Zooms one step about the middle of the graph view. With `animated` the view glides there.
        public func zoomStep(by factor: Double, in size: CGSize, animated: Bool) {
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            moveViewport(to: board.viewport.zoomed(by: factor, around: middle, in: size), animated: animated)
        }

        /// Shows the whole graph again. With `animated` the view glides there; Reduce Motion passes false.
        public func fit(animated: Bool) {
            moveViewport(to: .fit, animated: animated)
        }

        private func stopGlide() {
            viewportTask?.cancel()
            viewportTask = nil
        }

        private func moveViewport(to target: JourneyViewport, animated: Bool) {
            stopGlide()
            let start = board.viewport
            guard animated, start != target else {
                board.setViewport(target)
                return
            }
            viewportTask = Task { [weak self] in
                let steps = 12
                for step in 1...steps {
                    guard let self else { return }
                    do { try await self.pause(.milliseconds(16)) } catch { return }
                    guard !Task.isCancelled else { return }
                    let eased = JourneyViewport.eased(Double(step) / Double(steps))
                    self.board.setViewport(step == steps ? target : start.interpolated(to: target, progress: eased))
                }
                self?.viewportTask = nil
            }
        }

        // MARK: - Layout codes

        /// Applies a pasted layout code. Returns why it did not work, or nil when it did.
        @discardableResult
        public func applyLayoutCode(_ text: String) -> JourneyLayoutCode.Problem? {
            if let problem = JourneyLayoutCode.problem(with: text) { return problem }
            guard let decoded = try? JourneyLayoutCode.decode(text) else { return .damaged }
            stopGlide()
            board.apply(decoded)
            post("Layout applied.")
            return nil
        }

        // MARK: - Nodes

        /// Opens the sheet of a node.
        public func openNode(_ id: String) {
            guard let source, let node = board.graph.node(id: id), editor?.node.id != id else { return }
            editor = NodeEditorModel(node: node, backend: source.backend) { [weak self] finished, outcome in
                self?.finish(finished, outcome: outcome)
            }
        }

        /// Closes the node sheet.
        public func closeEditor() {
            editor = nil
        }

        /// A tap at `point` in a graph view of `size`. Opens the node under it. Returns true when there was one.
        @discardableResult
        public func tap(at point: CGPoint, in size: CGSize) -> Bool {
            guard let hit = board.node(at: point, in: size, tolerance: Self.tapTolerance) else { return false }
            openNode(hit.id)
            return true
        }

        private func finish(_ finished: NodeEditorModel, outcome: NodeEditorModel.Outcome) {
            if editor === finished { editor = nil }
            switch outcome {
            case .saved: post(finished.node.savedNotice)
            case .deleted: post(finished.node.deletedNotice)
            }
            Task { await refresh() }
        }

        // MARK: - Messages

        /// Shows a message over the content until ``dismissNotice(id:)`` removes it.
        public func post(_ text: String, isError: Bool = false) {
            noticeCount += 1
            notice = JourneyNotice(id: noticeCount, text: text, isError: isError)
        }

        /// Removes the message. With `id`, only that message goes, so a newer one stays.
        public func dismissNotice(id: Int? = nil) {
            guard id == nil || notice?.id == id else { return }
            notice = nil
        }

        /// Waits, then removes message `id` if it still shows. The view runs it while the message is on screen.
        public func expireNotice(id: Int, after delay: Duration = .seconds(6)) async {
            do { try await pause(delay) } catch { return }
            dismissNotice(id: id)
        }
    }
#endif
