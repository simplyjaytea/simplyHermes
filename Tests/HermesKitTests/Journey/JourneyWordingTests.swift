import Foundation
import HermesKit
import Testing

/// The words of the node sheet (WP-52). A delete promises what the server does: a skill is archived, a memory chunk is
/// removed, and a pinned skill is refused.
@Suite struct JourneyWordingTests {
    private let skill = JourneyNode(id: "daily-standup", category: "productivity", useCount: 25)
    private let pinnedSkill = JourneyNode(id: "swift-concurrency-review", category: "software", pinned: true)
    private let memory = JourneyNode(
        id: "memory:memory:0:3f9a1c2b", label: "JT likes short answers.", kind: .memory, memorySource: "memory",
        category: "memory", createdBy: "memory")
    private let other = JourneyNode(id: "rule-7", kind: .other("rule"))

    @Test func theConfirmationSaysSkillsAreArchivedAndMemoriesRemoved() {
        #expect(skill.deleteMessage.contains("archived"))
        #expect(skill.deleteMessage.contains("hermes curator restore daily-standup"))
        #expect(!skill.deleteMessage.contains("cannot be brought back"))
        #expect(memory.deleteMessage.contains("removed"))
        #expect(memory.deleteMessage.contains("cannot be brought back"))
        #expect(other.deleteMessage.contains("archived or removed"))
    }

    @Test func theTitleNamesWhatGoes() {
        #expect(skill.deleteTitle == "Delete \u{201C}daily-standup\u{201D}?")
        #expect(memory.deleteTitle == "Delete this memory?", "a memory's label is its first line, too long for a title")
        #expect(other.deleteTitle == "Delete \u{201C}rule-7\u{201D}?")
    }

    @Test func theNoticesAfterAChangeSayWhatHappened() {
        #expect(skill.deletedNotice == "Archived \u{201C}daily-standup\u{201D}.")
        #expect(memory.deletedNotice == "Removed the memory.")
        #expect(other.deletedNotice == "Deleted \u{201C}rule-7\u{201D}.")
        #expect(skill.savedNotice == "Saved \u{201C}daily-standup\u{201D}.")
        #expect(memory.savedNotice == "Saved the memory.")
    }

    @Test func aPinnedSkillSaysWhyItStays() {
        #expect(pinnedSkill.deleteBlocker == "A pinned skill cannot be deleted. Unpin it on the server first.")
        #expect(skill.deleteBlocker == nil && memory.deleteBlocker == nil)
    }

    @Test func voiceOverReadsTheNameThenTheFactsThenTheDate() throws {
        let dated = JourneyNode(
            id: "daily-standup", timestamp: 1_780_000_000, category: "productivity", useCount: 25, createdBy: "learn",
            pinned: true)
        let facts = "daily-standup, Skill, productivity, Learned, Pinned, Used 25 times"
        let day = try #require(dated.date).formatted(date: .abbreviated, time: .omitted)
        #expect(dated.spokenSummary == "\(facts), \(day)", "the date is last, written in the reader's own format")
        #expect(skill.spokenSummary == "daily-standup, Skill, productivity, Used 25 times")
        #expect(memory.spokenSummary == "JT likes short answers., Memory")
    }

    @Test func theSampleSourceServesTheSampleGraph() async throws {
        let source = JourneySource.sample()
        #expect(source.id == "sample" && source.name == "Preview server")
        #expect(try await source.backend.learningGraph() == JourneySample.graph)
        #expect(await source.currentProfile() == nil)
        #expect(JourneySource.sample(name: "Studio").name == "Studio")
    }
}
