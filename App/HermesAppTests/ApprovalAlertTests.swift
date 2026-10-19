import HermesUI
import Testing

@MainActor
struct ApprovalAlertTests {
    @Test func approvalInAnotherChatAlerts() throws {
        let model = ShellModel(selectedSessionID: "blog")

        #expect(model.needsApproval("backup"))
        let alert = try #require(model.approvalAlerts.first)
        #expect(alert.sessionID == "backup")
        #expect(alert.command == "ssh-copy-id backup@nas.local")
    }

    @Test func approvalInOpenChatDoesNotAlert() {
        let model = ShellModel(selectedSessionID: "backup")

        #expect(model.needsApproval("backup"))
        #expect(model.approvalAlerts.isEmpty)
    }

    @Test func settingsSectionAlertsForEveryChat() {
        let model = ShellModel(selectedSessionID: "backup")
        model.selectedSection = .settings

        #expect(model.approvalAlerts.map(\.sessionID) == ["backup"])
    }

    @Test func openingAlertedChatClearsBannerButKeepsBadge() {
        let model = ShellModel(selectedSessionID: "blog")

        model.open("backup")

        #expect(model.approvalAlerts.isEmpty)
        #expect(model.needsApproval("backup"))
    }

    @Test func approveAnswersAndClearsApproval() throws {
        let model = ShellModel(selectedSessionID: "blog")
        let alert = try #require(model.approvalAlerts.first)

        model.answer(alert, approved: true)

        #expect(!model.needsApproval("backup"))
        #expect(model.approvalAlerts.isEmpty)
    }
}
