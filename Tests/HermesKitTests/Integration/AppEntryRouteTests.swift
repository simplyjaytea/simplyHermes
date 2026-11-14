import Testing

@testable import HermesKit

struct AppEntryRouteTests {
    @Test func savedLocalChatsKeepTheShellWithNoServer() {
        #expect(
            AppEntryRoute.decide(hasServers: false, skipsOnboarding: false, hasLocalChats: true) == .shell,
            "Welcome must not hide chats the user has")
    }

    @Test func welcomeOnlyWhenThereIsNothingToShow() {
        #expect(AppEntryRoute.decide(hasServers: false, skipsOnboarding: false, hasLocalChats: false) == .welcome)
    }

    @Test func noFlashOfWelcomeWhileTheStoreIsRead() {
        #expect(AppEntryRoute.decide(hasServers: false, skipsOnboarding: false, hasLocalChats: nil) == .loading)
    }

    @Test(arguments: [true, false])
    func aServerOrSkipAlwaysShowsTheShell(local: Bool) {
        #expect(AppEntryRoute.decide(hasServers: true, skipsOnboarding: false, hasLocalChats: local) == .shell)
        #expect(AppEntryRoute.decide(hasServers: false, skipsOnboarding: true, hasLocalChats: nil) == .shell)
        #expect(
            AppEntryRoute.decide(hasServers: true, skipsOnboarding: false, hasLocalChats: nil) == .shell,
            "a saved server never waits for the local store")
    }
}
