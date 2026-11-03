import Foundation
import HermesKit
import Testing

/// Home-screen quick actions (feature B): routes, the planner, the menu and the stored last chat.
struct QuickActionsTests {
    private let localID = "local-\(UUID().uuidString)"
    private let serverA = "A-0000"
    private let serverB = "B-0000"

    private func plan(
        _ route: QuickActionRoute, active: String? = "A-0000", saved: Set<String> = ["A-0000", "B-0000"],
        localExists: Bool = true
    ) -> QuickActionOutcome {
        QuickActionPlanner.outcome(
            for: route, activeConnectionID: active, savedConnectionIDs: saved, localChatExists: { _ in localExists })
    }

    // MARK: Type to route

    @Test func everyRouteSurvivesTheShortcutItemRoundTrip() {
        let routes: [QuickActionRoute] = [
            .newChat, .searchChats, .openChat(.server("s1", connectionID: serverA)), .openChat(.local(localID)),
        ]
        for route in routes {
            #expect(QuickActionRoute(type: route.type, userInfo: route.userInfo) == route)
        }
    }

    @Test func malformedItemsOpenNothing() {
        let open = QuickActionRoute.openChat(.server("s1", connectionID: serverA)).type
        #expect(QuickActionRoute(type: "com.other.app.newChat", userInfo: [:]) == nil)
        #expect(QuickActionRoute(type: open, userInfo: ["kind": "server", "chat": "s1"]) == nil, "no server")
        #expect(QuickActionRoute(type: open, userInfo: ["kind": "local", "chat": "s1"]) == nil, "not a local id")
        #expect(
            QuickActionRoute(type: open, userInfo: ["kind": "server", "chat": localID, "connection": serverA]) == nil,
            "a local id can't pose as a server chat")
        #expect(QuickActionRoute(type: open, userInfo: ["kind": "both", "chat": "s1"]) == nil)
    }

    // MARK: Planner

    @Test func newChatAndSearchMapStraightThrough() {
        #expect(plan(.newChat) == .newChat)
        #expect(plan(.searchChats) == .searchChats)
    }

    @Test func aServerChatOnTheActiveServerOpensExactlyThatChat() {
        #expect(plan(.openChat(.server("s1", connectionID: serverA))) == .open(chatID: "s1"))
    }

    @Test func aServerChatOnAnotherSavedServerSwitchesServerFirst() {
        #expect(
            plan(.openChat(.server("s1", connectionID: serverB)))
                == .switchServerThenOpen(connectionID: serverB, chatID: "s1"))
    }

    /// User rule: no auto-switch to local. The planner can't see reachability, and a server chat never yields a local
    /// chat, whatever the local store holds or which server is active.
    @Test func aServerChatNeverRoutesToALocalChat() {
        let route = QuickActionRoute.openChat(.server("s1", connectionID: serverA))
        for active in [serverA, serverB, nil] as [String?] {
            for localExists in [true, false] {
                let outcome = plan(route, active: active, localExists: localExists)
                switch outcome {
                case .open(let id), .switchServerThenOpen(_, let id):
                    #expect(id == "s1")
                    #expect(!id.hasPrefix("local-"))
                case .newChat, .searchChats, .stale:
                    Issue.record("A saved server's chat must open that chat, got \(outcome)")
                }
            }
        }
    }

    @Test func aRemovedServerMakesItsChatShortcutStaleNotLocal() {
        #expect(plan(.openChat(.server("s1", connectionID: "gone"))) == .stale)
    }

    @Test func aLocalChatOpensWhenItExistsAndIsStaleWhenDeleted() {
        #expect(plan(.openChat(.local(localID))) == .open(chatID: localID))
        #expect(plan(.openChat(.local(localID)), localExists: false) == .stale)
    }

    // MARK: Menu and title toggle

    @Test func theMenuIsNewChatSearchThenTheLastChatWithItsTitle() {
        let last = QuickActionLastChat(chat: .server("s1", connectionID: serverA), title: "Backup job")
        let items = QuickActionMenu.items(lastChat: last, showTitle: true)
        #expect(items.map(\.title) == ["New chat", "Search chats", "Backup job"])
        #expect(items[2].subtitle == "Last chat")
        #expect(items[2].route == .openChat(last.chat))
    }

    @Test func hidingTitlesSaysContinueLastChat() {
        let last = QuickActionLastChat(chat: .local(localID), title: "Private plans")
        let item = QuickActionMenu.items(lastChat: last, showTitle: false)[2]
        #expect(item.title == "Continue last chat")
        #expect(item.subtitle == nil)
        #expect(!item.title.contains("Private"))
        #expect(item.symbol == "iphone")
    }

    @Test func anEmptyTitleAlsoSaysContinueLastChat() {
        let last = QuickActionLastChat(chat: .local(localID), title: "  ")
        #expect(QuickActionMenu.items(lastChat: last, showTitle: true)[2].title == "Continue last chat")
    }

    @Test func noLastChatMeansOnlyTheFixedItems() {
        #expect(QuickActionMenu.items(lastChat: nil, showTitle: true).count == 2)
    }

    @Test func theTitleSettingIsOnByDefaultAndStored() throws {
        let defaults = try #require(UserDefaults(suiteName: "quick-\(UUID().uuidString)"))
        let store = QuickActionStore(defaults: defaults)
        #expect(store.showTitle)
        defaults.set(false, forKey: QuickActionStore.showTitleKey)
        #expect(!store.showTitle)
        let last = QuickActionLastChat(chat: .local(localID), title: "T")
        store.lastChat = last
        #expect(QuickActionStore(defaults: defaults).lastChat == last, "Kept across a relaunch")
    }

    // MARK: Deleted chats

    @Test func aDeletedLocalChatLeavesTheMenu() {
        let last = QuickActionLastChat(chat: .local(localID), title: "T")
        #expect(
            !QuickActionMenu.keeps(
                last, savedConnectionIDs: [], listedServerChats: nil, localChatExists: { _ in false }))
        #expect(
            QuickActionMenu.keeps(last, savedConnectionIDs: [], listedServerChats: nil, localChatExists: { _ in true }))
    }

    @Test func aServerChatLeavesOnlyOnceTheLoadedListLacksIt() {
        let last = QuickActionLastChat(chat: .server("s1", connectionID: serverA), title: "T")
        func keeps(_ listed: Set<String>?, saved: Set<String> = ["A-0000"]) -> Bool {
            QuickActionMenu.keeps(
                last, savedConnectionIDs: saved, listedServerChats: listed, localChatExists: { _ in true })
        }
        #expect(keeps(nil), "List not loaded yet: keep it")
        #expect(keeps(["s1", "s2"]))
        #expect(!keeps(["s2"]), "Deleted on the server")
        #expect(!keeps(["s1"], saved: []), "Server removed")
    }
}
