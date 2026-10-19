import Foundation
import Testing

@testable import HermesKit

@Suite struct TerminalTabsTests {
    @Test func openSelectsTheNewTabAndNumbersIt() {
        var tabs = TerminalTabs()
        let first = tabs.open()
        let second = tabs.open()
        #expect(tabs.tabs.map(\.title) == ["Terminal 1", "Terminal 2"])
        #expect(tabs.selectedID == second.id)
        #expect(first.attachToken != second.attachToken)
    }

    @Test func numbersDoNotReuseAfterClose() {
        var tabs = TerminalTabs()
        let first = tabs.open()
        tabs.close(first.id)
        #expect(tabs.open().title == "Terminal 2")
    }

    @Test func selectIgnoresUnknownIds() {
        var tabs = TerminalTabs()
        let first = tabs.open()
        _ = tabs.open()
        tabs.select(first.id)
        tabs.select(UUID())
        #expect(tabs.selectedID == first.id)
    }

    @Test func closingTheSelectedTabSelectsTheOneBeforeIt() {
        var tabs = TerminalTabs()
        _ = tabs.open()
        let middle = tabs.open()
        _ = tabs.open()
        tabs.select(middle.id)
        tabs.close(middle.id)
        #expect(tabs.tabs.count == 2)
        #expect(tabs.selected?.title == "Terminal 1")
    }

    @Test func closingTheFirstSelectedTabSelectsTheNextOne() {
        var tabs = TerminalTabs()
        let first = tabs.open()
        let second = tabs.open()
        tabs.select(first.id)
        tabs.close(first.id)
        #expect(tabs.selectedID == second.id)
    }

    @Test func closingAnUnselectedTabKeepsTheSelection() {
        var tabs = TerminalTabs()
        let first = tabs.open()
        let second = tabs.open()
        tabs.close(first.id)
        #expect(tabs.selectedID == second.id)
    }

    @Test func closingTheLastTabClearsTheSelection() {
        var tabs = TerminalTabs()
        let only = tabs.open()
        tabs.close(only.id)
        #expect(tabs.tabs.isEmpty)
        #expect(tabs.selected == nil)
    }
}
