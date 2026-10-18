import Foundation
import Testing

@testable import HermesKit

@Suite struct NewAgentDraftTests {
    @Test func blocksMissingReservedInvalidAndTakenNames() {
        #expect(NewAgentDraft(name: "  ").problems(existingProfiles: []) == [.nameMissing])
        #expect(NewAgentDraft(name: "Hermes").problems(existingProfiles: []) == [.nameReserved])
        #expect(NewAgentDraft(name: "!!!").problems(existingProfiles: []) == [.nameInvalid])
        #expect(NewAgentDraft(name: "Ops").problems(existingProfiles: ["ops"]) == [.nameTaken])
        #expect(NewAgentDraft(name: "Ops").problems(existingProfiles: []).isEmpty)
    }

    @Test func modelPinNeedsProviderAndModelTogether() {
        #expect(NewAgentDraft(name: "ops", provider: "openai").problems(existingProfiles: []) == [.modelIncomplete])
        #expect(NewAgentDraft(name: "ops", model: "gpt").problems(existingProfiles: []) == [.modelIncomplete])
        #expect(NewAgentDraft(name: "ops", provider: "openai", model: "gpt").problems(existingProfiles: []).isEmpty)
    }

    @Test func shownTitleFallsBackToTheNameOnlyWhenItIsNotAscii() {
        #expect(NewAgentDraft(name: "Ops").shownTitle == "")
        #expect(NewAgentDraft(name: "東京").shownTitle == "東京")
        #expect(NewAgentDraft(name: "Ops", title: " Ops Bot ").shownTitle == "Ops Bot")
    }

    @Test func generatedSoulCarriesRoleAndMission() {
        let soul = NewAgentDraft(name: "ops", title: "Ops", roleDescription: "Runs deploys").resolvedSoul
        #expect(soul.hasPrefix("# Ops\n\n**Role:** Ops\n**Mission:** Runs deploys\n\n"))
        #expect(soul.contains("(profile `ops`)"))
    }

    @Test func customSoulWinsOverTheGeneratedOne() {
        #expect(NewAgentDraft(name: "ops", soul: "  Be terse.  ").resolvedSoul == "Be terse.")
    }

    @Test func createParamsCloneUnlessNoSkills() {
        let cloned = NewAgentDraft(
            name: "Ops Two", title: "Ops", roleDescription: "Runs deploys", provider: "openai", model: "gpt"
        ).createParams()
        #expect(cloned.name == "ops-two")
        #expect(cloned.cloneFrom == "default")
        #expect(cloned.noSkills == false)
        #expect(cloned.description == "Ops — Runs deploys")
        #expect(cloned.provider == "openai")
        #expect(cloned.model == "gpt")
        #expect(cloned.shareAuth == true)

        let fresh = NewAgentDraft(name: "ops", noSkills: true).createParams()
        #expect(fresh.cloneFrom == nil)
        #expect(fresh.noSkills == true)
        #expect(fresh.description == nil)
        #expect(fresh.model == nil)
    }

    @Test func stagedParamsOnlyWhenSomethingChanged() {
        #expect(NewAgentDraft(name: "ops").stagedConfigureParams() == nil)
        let staged = NewAgentDraft(name: "ops", disabledSkills: ["x"]).stagedConfigureParams()
        #expect(staged?.name == "ops")
        #expect(staged?.disabledSkills == ["x"])
    }
}
