import Testing

@testable import HermesKit

struct ChatSearchFilterTests {
    private let row = ["Backup cron failed", "rsync: connection closed", "home-server"]

    @Test func aBlankQueryMatchesEverything() {
        #expect(ChatSearchFilter.matches("", in: row))
        #expect(ChatSearchFilter.matches("   ", in: row))
        #expect(ChatSearchFilter.matches("", in: []))
    }

    @Test func caseAndAccentsDoNotMatter() {
        #expect(ChatSearchFilter.matches("BACKUP", in: row))
        #expect(ChatSearchFilter.matches("cafe", in: ["Café plans"]))
    }

    @Test func everyWordMustAppearSomewhereInAnyOrder() {
        #expect(ChatSearchFilter.matches("cron home", in: row), "title and server")
        #expect(ChatSearchFilter.matches("rsync backup", in: row), "subtitle and title, reversed")
        #expect(!ChatSearchFilter.matches("cron garden", in: row), "one word missing")
    }

    @Test func aWordIsNotFoundAcrossTwoFields() {
        #expect(!ChatSearchFilter.matches("failedrsync", in: row))
    }
}
