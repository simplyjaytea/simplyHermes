import Foundation
import HermesKit
import HermesUI
import Testing

/// The memory screen's model (WP-52): loading, switching server and profile, view settings, taps, messages and layout
/// codes. The views only forward touches to it, so these tests cover what the screen does.
@MainActor
@Suite struct MemoryJourneyModelTests {
    private let size = CGSize(width: 390, height: 700)

    private func source(
        _ id: String = "server-a", backend: any JourneyBackend = SampleJourneyBackend(),
        profile: @escaping @Sendable () async -> String? = { nil }
    ) -> JourneySource {
        JourneySource(id: id, name: "Server \(id)", backend: backend, currentProfile: profile)
    }

    private func loadedModel(backend: any JourneyBackend = SampleJourneyBackend()) async -> MemoryJourneyModel {
        let model = MemoryJourneyModel(pause: noPause)
        await model.attach(source(backend: backend))
        return model
    }

    // MARK: - Loading

    @Test func startsWithNoServer() {
        let model = MemoryJourneyModel()
        #expect(model.phase == .notConnected && model.board.isEmpty && model.serverName == nil)
        #expect(!model.isRefreshing && model.notice == nil && model.editor == nil)
    }

    @Test func attachLoadsTheGraph() async {
        let model = await loadedModel()
        #expect(model.phase == .loaded)
        #expect(model.board.graph.nodes.count == JourneySample.graph.nodes.count)
        #expect(model.serverName == "Server server-a" && !model.isRefreshing && !model.isEmptyGraph)
    }

    @Test func attachWithNoServerShowsTheNoServerState() async {
        let model = await loadedModel()
        await model.attach(nil)
        #expect(model.phase == .notConnected && model.board.isEmpty && model.serverName == nil)
        await model.refresh()
        #expect(model.phase == .notConnected, "a refresh with no server stays put")
    }

    @Test func anEmptyGraphIsLoadedButEmpty() async {
        let backend = ScriptedJourneyBackend(graph: { _ in JourneyGraph() })
        let model = await loadedModel(backend: backend)
        #expect(model.phase == .loaded && model.isEmptyGraph)
    }

    @Test func aFailedFirstLoadShowsTheReasonAndRetryRecovers() async {
        let backend = ScriptedJourneyBackend(graph: { call in
            if call == 1 { throw RESTError.http(status: 500, detail: nil) }
            return JourneySample.graph
        })
        let model = await loadedModel(backend: backend)
        guard case .failed(let text) = model.phase else {
            Issue.record("expected a failed phase, got \(model.phase)")
            return
        }
        #expect(text.hasPrefix("Could not load memory.") && text.contains("500"))
        #expect(model.board.isEmpty)
        await model.refresh()
        #expect(model.phase == .loaded && model.board.graph.nodes.count == JourneySample.graph.nodes.count)
    }

    @Test func aFailedLaterLoadKeepsTheGraphAndPostsANotice() async {
        let backend = ScriptedJourneyBackend(graph: { call in
            if call == 2 { throw RESTError.transport("offline") }
            return JourneySample.graph
        })
        let model = await loadedModel(backend: backend)
        let before = model.board.graph
        await model.refresh()
        #expect(model.phase == .loaded && model.board.graph == before && !model.isRefreshing)
        #expect(model.notice?.isError == true && model.notice?.text.hasPrefix("Could not load memory.") == true)
    }

    @Test func aRefreshKeepsFilterScrubAndZoom() async {
        let model = await loadedModel()
        model.setFilter(.learned)
        model.setScrub(0.6)
        model.zoom(by: 2, around: CGPoint(x: 100, y: 100), in: size)
        let viewport = model.board.viewport
        await model.refresh()
        #expect(model.board.filter == .learned && model.board.scrub == 0.6 && model.board.viewport == viewport)
    }

    @Test func askingAgainWhileALoadRunsJoinsIt() async {
        let gated = GatedJourneyBackend(graph: JourneySample.graph)
        let model = MemoryJourneyModel(pause: noPause)
        let first = Task { await model.attach(source(backend: gated)) }
        #expect(await waitUntil { await gated.waitingCount == 1 })
        #expect(model.phase == .loading)
        let second = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await gated.waitingCount == 1, "no second call goes to the server")
        await gated.release()
        await first.value
        await second.value
        #expect(model.phase == .loaded)
    }

    @Test func sameServerReloadsWithoutClearing() async {
        let backend = ScriptedJourneyBackend()
        let model = await loadedModel(backend: backend)
        model.setFilter(.used)
        await model.attach(source(backend: backend))
        #expect(await backend.graphCalls == 2 && model.board.filter == .used && model.phase == .loaded)
    }

    @Test func anotherServerDropsTheOldGraphAndALateAnswer() async {
        let slow = GatedJourneyBackend(graph: profileGraph("slow"))
        let model = MemoryJourneyModel(pause: noPause)
        let first = Task { await model.attach(source("slow-server", backend: slow)) }
        #expect(await waitUntil { await slow.waitingCount == 1 })
        await model.attach(source("fast-server", backend: ScriptedJourneyBackend(graph: { _ in profileGraph("fast") })))
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-fast"] && model.serverName == "Server fast-server")
        await slow.release()
        await first.value
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-fast"], "the old server's answer is ignored")
        #expect(model.phase == .loaded && !model.isRefreshing)
    }

    @Test func switchingServerClearsTheOpenSheetAndMessages() async {
        let model = await loadedModel()
        model.openNode("daily-standup")
        model.post("Hello")
        await model.attach(source("server-b"))
        #expect(model.editor == nil && model.notice == nil)
    }

    // MARK: - Profiles

    @Test func aSwitchOfProfileLoadsThatProfilesGraph() async {
        let box = ProfileBox("alpha")
        let backend = ScriptedJourneyBackend(graph: { _ in profileGraph(await box.value ?? "default") })
        let model = MemoryJourneyModel(pause: noPause)
        await model.attach(source(backend: backend, profile: { await box.value }))
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-alpha"])
        await model.checkProfile()
        #expect(await backend.graphCalls == 1, "the same profile loads nothing")
        await box.set("beta")
        model.setFilter(.used)
        await model.checkProfile()
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-beta"] && model.phase == .loaded)
        #expect(model.board.filter == .all, "a new profile starts with a fresh view")
        #expect(await backend.graphCalls == 2)
    }

    @Test func theProfileWatcherChecksOnATimerUntilCancelled() async {
        let box = ProfileBox(nil)
        let backend = ScriptedJourneyBackend(graph: { _ in profileGraph(await box.value ?? "default") })
        let pauses = CallCounter()
        let model = MemoryJourneyModel(pause: { _ in
            let call = pauses.next()
            if call == 1 { await box.set("late") }
            if call >= 4 { throw CancellationError() }
        })
        await model.attach(source(backend: backend, profile: { await box.value }))
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-default"])
        await model.watchProfile(every: .seconds(3))
        #expect(model.board.graph.nodes.map(\.id) == ["skill-of-late"])
        #expect(pauses.count == 4, "poll, settle, poll, poll that ends the loop")
    }

    @Test func aProfileSwitchWhileLoadingDropsTheOldAnswer() async {
        let box = ProfileBox("one")
        let gate = GatedJourneyBackend(graph: profileGraph("one"))
        let model = MemoryJourneyModel(pause: noPause)
        let loading = Task { await model.attach(source(backend: gate, profile: { await box.value })) }
        #expect(await waitUntil { await gate.waitingCount == 1 })
        await box.set("two")
        let switching = Task { await model.checkProfile() }
        #expect(await waitUntil { await gate.waitingCount == 2 })
        await gate.release()
        await loading.value
        await switching.value
        #expect(model.phase == .loaded && model.board.graph.nodes.count == 1)
    }

    // MARK: - View settings

    @Test func filterScrubAndViewportGoToTheBoard() async {
        let model = await loadedModel()
        model.setFilter(.used)
        #expect(model.board.filter == .used && model.board.rows.count == model.board.count(.used))
        model.setScrub(0.25)
        #expect(model.board.scrub == 0.25)
        model.zoom(by: 4, around: CGPoint(x: 195, y: 350), in: size)
        #expect(model.board.viewport.zoom == 4)
        model.pan(by: CGSize(width: 40, height: 0), in: size)
        #expect(model.board.viewport.center.x < 0, "the graph follows the finger")
        model.fit(animated: false)
        #expect(model.board.viewport == .fit)
    }

    @Test func zoomStepsKeepTheMiddleOfTheView() async {
        let model = await loadedModel()
        model.zoomStep(by: 2, in: size, animated: false)
        #expect(model.board.viewport.zoom == 2 && model.board.viewport.center == .zero)
        model.zoomStep(by: 100, in: size, animated: false)
        #expect(model.board.viewport.zoom == JourneyViewport.zoomRange.upperBound)
    }

    @Test func anAnimatedFitGlidesToTheTarget() async {
        let model = await loadedModel()
        model.zoom(by: 4, around: CGPoint(x: 50, y: 60), in: size)
        model.fit(animated: true)
        #expect(await waitUntil { model.board.viewport == .fit })
    }

    @Test func aTouchStopsAGlide() async {
        let model = await loadedModel()
        model.zoom(by: 4, around: CGPoint(x: 50, y: 60), in: size)
        model.fit(animated: true)
        model.pan(by: CGSize(width: 10, height: 10), in: size)
        let touched = model.board.viewport
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.board.viewport == touched, "the glide ended when the finger came down")
        #expect(touched != .fit)
    }

    // MARK: - Taps and the sheet

    @Test func aTapOpensTheNodeUnderTheFinger() async throws {
        let model = await loadedModel()
        let node = try #require(model.board.scene.nodes.first)
        let point = model.board.viewport.toView(node.position, in: size)
        #expect(model.tap(at: CGPoint(x: point.x + 3, y: point.y - 2), in: size))
        #expect(model.editor?.node.id == node.id && model.selectedID == node.id)
        model.closeEditor()
        #expect(model.editor == nil && model.selectedID == nil)
    }

    @Test func aTapOnNothingOpensNothing() async {
        let model = await loadedModel()
        #expect(!model.tap(at: CGPoint(x: 1, y: 1), in: size))
        #expect(!model.tap(at: .zero, in: .zero))
        #expect(model.editor == nil)
    }

    @Test func onlyKnownNodesOpen() async {
        let model = await loadedModel()
        model.openNode("no-such-node")
        #expect(model.editor == nil)
        model.openNode("daily-standup")
        let first = model.editor
        model.openNode("daily-standup")
        #expect(model.editor === first, "opening the open node again changes nothing")
        let none = MemoryJourneyModel()
        none.openNode("daily-standup")
        #expect(none.editor == nil, "without a server nothing opens")
    }

    @Test func aSavedEditClosesTheSheetPostsANoticeAndReloads() async throws {
        let backend = ScriptedJourneyBackend()
        let model = await loadedModel(backend: backend)
        model.openNode("daily-standup")
        let editor = try #require(model.editor)
        await editor.load()
        editor.beginEditing()
        editor.draft += "\nOne more line."
        await editor.save()
        #expect(model.editor == nil)
        #expect(model.notice?.text == "Saved \u{201C}\(editor.node.label)\u{201D}." && model.notice?.isError == false)
        #expect(await waitUntil { await backend.graphCalls == 2 })
        #expect(await backend.updates.count == 1)
    }

    @Test func aDeletedSkillIsArchivedAndStaysInTheGraph() async throws {
        let model = await loadedModel()
        model.openNode("daily-standup")
        let editor = try #require(model.editor)
        await editor.load()
        await editor.delete()
        #expect(model.editor == nil && model.notice?.text.hasPrefix("Archived") == true)
        await model.refresh()
        #expect(model.board.graph.node(id: "daily-standup")?.state == "archived")
    }

    @Test func aDeletedMemoryIsRemovedFromTheGraph() async throws {
        let model = await loadedModel()
        let memory = try #require(model.board.graph.nodes.first { $0.kind == .memory })
        let before = model.board.graph.nodes.count
        model.openNode(memory.id)
        let editor = try #require(model.editor)
        await editor.load()
        await editor.delete()
        #expect(model.notice?.text == "Removed the memory.")
        await model.refresh()
        #expect(model.board.graph.nodes.count == before - 1 && model.board.graph.node(id: memory.id) == nil)
    }

    @Test func aFinishedSheetThatIsNoLongerOpenLeavesTheCurrentSheetAlone() async throws {
        let model = await loadedModel()
        model.openNode("daily-standup")
        let old = try #require(model.editor)
        await old.load()
        model.closeEditor()
        model.openNode("svg-diagrams")
        let current = try #require(model.editor)
        old.beginEditing()
        old.draft += "x"
        await old.save()
        #expect(model.editor === current, "a late save from a closed sheet does not close the new one")
    }

    // MARK: - Messages

    @Test func messagesCarryGrowingIds() {
        let model = MemoryJourneyModel()
        model.post("One")
        let first = model.notice?.id
        model.post("One")
        #expect(model.notice?.id != first && model.notice?.text == "One" && model.notice?.isError == false)
        model.post("Two", isError: true)
        #expect(model.notice?.isError == true)
        model.dismissNotice()
        #expect(model.notice == nil)
    }

    @Test func aMessageExpiresUnlessANewerOneReplacedIt() async {
        let model = MemoryJourneyModel(pause: noPause)
        model.post("Old")
        let old = model.notice?.id ?? 0
        model.post("New")
        await model.expireNotice(id: old)
        #expect(model.notice?.text == "New", "an old timer does not remove a newer message")
        await model.expireNotice(id: model.notice?.id ?? 0)
        #expect(model.notice == nil)
    }

    @Test func aCancelledTimerKeepsTheMessage() async {
        let model = MemoryJourneyModel(pause: { _ in throw CancellationError() })
        model.post("Stay")
        await model.expireNotice(id: model.notice?.id ?? 0)
        #expect(model.notice?.text == "Stay")
    }

    // MARK: - Layout codes

    @Test func aLayoutCodeCarriesTheViewToAnotherModel() async {
        let first = await loadedModel()
        first.setFilter(.learned)
        first.setScrub(0.8)
        first.zoom(by: 3, around: CGPoint(x: 100, y: 200), in: size)
        let code = first.layoutCode
        #expect(code.hasPrefix(JourneyLayoutCode.versionPrefix))

        let second = await loadedModel()
        #expect(second.applyLayoutCode(code) == nil)
        #expect(second.board.filter == .learned)
        #expect(abs(second.board.scrub - 0.8) < 0.001)
        #expect(abs(second.board.viewport.zoom - first.board.viewport.zoom) < 0.001)
        #expect(second.notice?.text == "Layout applied.")
        #expect(second.board.rows.count == second.board.count(.learned), "the list follows the filter from the code")
    }

    @Test func aBadLayoutCodeChangesNothing() async {
        let model = await loadedModel()
        let before = model.board
        #expect(model.applyLayoutCode("") == .empty)
        #expect(model.applyLayoutCode("hello") == .notACode)
        #expect(model.applyLayoutCode("HJ9.AAAA") != nil)
        #expect(model.applyLayoutCode(String(model.layoutCode.dropLast(3))) == .damaged)
        #expect(model.board == before && model.notice == nil)
    }

    @Test func aWrappedLayoutCodeStillWorks() async {
        let model = await loadedModel()
        let code = model.layoutCode
        let wrapped = "  \(code.prefix(8))\n\(code.dropFirst(8)) \n"
        #expect(model.applyLayoutCode(wrapped) == nil)
    }

    // MARK: - Previews

    @Test func theSampleModelIsReadyWithoutAServer() throws {
        let model = MemoryJourneyModel.sample()
        #expect(model.phase == .loaded && model.board.graph == JourneySample.graph)
        #expect(model.serverName == "Preview server")
        model.openNode("daily-standup")
        #expect(model.editor != nil)
    }
}
