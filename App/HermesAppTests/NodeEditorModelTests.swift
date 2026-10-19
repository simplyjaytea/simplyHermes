import Foundation
import HermesKit
import HermesUI
import Testing

/// The node sheet's flow (WP-52): read, edit, save, delete with a confirmation, and the words that go with them.
@MainActor
@Suite struct NodeEditorModelTests {
    /// Collects how the flow ended.
    @MainActor
    final class Finishes {
        var outcomes: [NodeEditorModel.Outcome] = []
    }

    private let skill = JourneyNode(id: "daily-standup", category: "productivity", useCount: 25)
    private let pinnedSkill = JourneyNode(id: "swift-concurrency-review", category: "software", pinned: true)
    private let memory = JourneyNode(
        id: "memory:memory:0:3f9a1c2b", label: "JT likes short answers.", kind: .memory, memorySource: "memory",
        category: "memory", createdBy: "memory")

    private func editor(
        _ node: JourneyNode, backend: any JourneyBackend = ScriptedJourneyBackend(), finishes: Finishes = Finishes()
    ) -> NodeEditorModel {
        NodeEditorModel(node: node, backend: backend) { _, outcome in finishes.outcomes.append(outcome) }
    }

    @Test func opensWithTheFullText() async {
        let backend = ScriptedJourneyBackend(detail: .success(JourneyNodeDetail(content: "# Daily standup\nBody")))
        let model = editor(skill, backend: backend)
        #expect(model.phase == .loading && model.isBusy && model.id == "daily-standup")
        await model.load()
        #expect(model.phase == .viewing && model.content == "# Daily standup\nBody" && model.draft == model.content)
        #expect(model.canEdit && model.canDelete && !model.isBusy && !model.isEditing)
    }

    @Test func aFailedOpenCanBeTriedAgain() async {
        let backend = ScriptedJourneyBackend(detail: .failure(RESTError.http(status: 404, detail: nil)))
        let model = editor(skill, backend: backend)
        await model.load()
        guard case .failed(let text) = model.phase else {
            Issue.record("expected a failed phase, got \(model.phase)")
            return
        }
        #expect(text.hasPrefix("Could not open that item.") && !model.canEdit)
        #expect(model.canDelete, "a node that will not open can still be deleted")
        await backend.setDetail(.success(JourneyNodeDetail(content: "Back again")))
        await model.load()
        #expect(model.phase == .viewing && model.content == "Back again")
    }

    @Test func loadingTwiceDoesNotStartOver() async {
        let model = editor(skill)
        await model.load()
        model.beginEditing()
        model.draft = "typed"
        await model.load()
        #expect(model.phase == .editing && model.draft == "typed", "a late second load must not wipe the editor")
    }

    @Test func editingStartsFromTheServersTextAndCancelDropsTheChanges() async {
        let model = editor(skill)
        model.beginEditing()
        #expect(model.phase == .loading, "nothing to edit before the text arrived")
        await model.load()
        model.beginEditing()
        #expect(model.phase == .editing && model.isEditing && !model.hasChanges && !model.canSave)
        model.draft += " more"
        #expect(model.hasChanges && model.canSave)
        model.cancelEditing()
        #expect(model.phase == .viewing && model.draft == model.content && !model.hasChanges)
    }

    @Test func anEmptyEditCannotBeSaved() async {
        let model = editor(skill)
        await model.load()
        model.beginEditing()
        model.draft = " \n\t "
        #expect(model.hasChanges && !model.canSave)
        await model.save()
        #expect(model.phase == .editing, "the save did not go anywhere")
    }

    @Test func aSavedEditEndsTheFlowOnce() async {
        let backend = ScriptedJourneyBackend(detail: .success(JourneyNodeDetail(content: "old")))
        let finishes = Finishes()
        let model = editor(skill, backend: backend, finishes: finishes)
        await model.load()
        model.beginEditing()
        model.draft = "new text"
        await model.save()
        #expect(finishes.outcomes == [.saved])
        #expect(await backend.updates == ["daily-standup=new text"])
        #expect(model.phase == .viewing && model.content == "new text")
        await model.save()
        #expect(finishes.outcomes == [.saved], "nothing changed, so a second save sends nothing")
    }

    @Test func aRefusedEditKeepsTheTextAndSaysWhy() async {
        let backend = ScriptedJourneyBackend(
            update: .failure(RESTError.http(status: 400, detail: "Invalid SKILL.md: missing name")))
        let finishes = Finishes()
        let model = editor(skill, backend: backend, finishes: finishes)
        await model.load()
        model.beginEditing()
        model.draft = "no front matter"
        await model.save()
        #expect(model.phase == .editing && model.draft == "no front matter")
        #expect(model.problem == "Could not save your change. The server said: Invalid SKILL.md: missing name")
        #expect(finishes.outcomes.isEmpty)
        model.draft = "---\nname: x\n---"
        await backend.setUpdate(.success(JourneyMutationResult(ok: true)))
        await model.save()
        #expect(finishes.outcomes == [.saved] && model.problem == nil)
    }

    @Test func aSkillDeleteAsksFirstAndEndsTheFlow() async {
        let backend = ScriptedJourneyBackend(delete: .success(JourneyMutationResult(ok: true, message: "archived")))
        let finishes = Finishes()
        let model = editor(skill, backend: backend, finishes: finishes)
        await model.load()
        model.requestDelete()
        #expect(model.confirmsDelete && finishes.outcomes.isEmpty && model.phase == .viewing)
        await model.delete()
        #expect(!model.confirmsDelete && finishes.outcomes == [.deleted])
        #expect(await backend.deletions == ["daily-standup"])
    }

    @Test func aRefusedDeleteGoesBackToReading() async {
        let backend = ScriptedJourneyBackend(
            delete: .failure(RESTError.http(status: 409, detail: "daily-standup is pinned. Unpin it before deleting.")))
        let finishes = Finishes()
        let model = editor(skill, backend: backend, finishes: finishes)
        await model.load()
        await model.delete()
        #expect(model.phase == .viewing && finishes.outcomes.isEmpty)
        #expect(model.problem?.hasPrefix("Could not delete that item.") == true)
        #expect(model.problem?.contains("pinned") == true)
    }

    @Test func aPinnedSkillCannotBeDeleted() async {
        let backend = ScriptedJourneyBackend()
        let model = editor(pinnedSkill, backend: backend)
        await model.load()
        #expect(!model.canDelete && model.node.deleteBlocker?.contains("Unpin") == true)
        model.requestDelete()
        #expect(!model.confirmsDelete)
        await model.delete()
        #expect(await backend.deletions.isEmpty)
    }

    @Test func aDeleteIsOnlyOfferedWhileReading() async {
        let model = editor(skill)
        #expect(!model.canDelete, "not while the text is on its way")
        await model.load()
        model.beginEditing()
        #expect(!model.canDelete, "not while typing")
        model.requestDelete()
        #expect(!model.confirmsDelete)
    }
}
