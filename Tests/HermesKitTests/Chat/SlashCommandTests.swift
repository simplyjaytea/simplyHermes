import Testing

@testable import HermesKit

@Suite struct SlashCommandTests {
    @Test func nameWithoutAnArgument() throws {
        let command = try #require(SlashCommand("/compress"))
        #expect(command.name == "compress")
        #expect(command.arg == nil)
    }

    @Test func argumentIsTheTrimmedTextAfterTheName() throws {
        let command = try #require(SlashCommand("/review  staged \n more "))
        #expect(command.name == "review")
        #expect(command.arg == "staged \n more")
    }

    @Test func textWithoutASlashAndANameIsNotACommand() {
        #expect(SlashCommand("compress") == nil)
        #expect(SlashCommand("/") == nil)
        #expect(SlashCommand("/ compress") == nil)
    }
}
