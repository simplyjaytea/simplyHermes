import XCTest

/// Feature "Message actions": the long-press menu on a chat message offers Copy, Share, Quote in reply and Select
/// text. Quote only fills the draft; nothing is sent.
final class MessageActionsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuOffersCopyShareQuoteAndSelectText() {
        let app = launch()
        openMenu(on: visibleAnswer(app))
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share…"].exists)
        XCTAssertTrue(app.buttons["Quote in reply"].exists)
        XCTAssertTrue(app.buttons["Select text"].exists)

        app.buttons["Share…"].tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 10), "Share should open the system share sheet")
    }

    @MainActor
    func testQuoteInReplyFillsTheDraftWithoutSending() {
        let app = launch()
        let answer = visibleAnswer(app)
        XCTAssertEqual(newMessages(app).count, 0, "The sample chat starts with its own messages only")
        openMenu(on: answer)
        XCTAssertTrue(app.buttons["Quote in reply"].waitForExistence(timeout: 5))
        app.buttons["Quote in reply"].tap()

        let field = app.textViews["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let draft = field.value as? String ?? ""
        XCTAssertTrue(draft.hasPrefix("> Answer"), "The draft should start with the quote, got: \(draft)")
        // Nothing was sent. Counting visible rows can't tell: the transcript is lazy, and once the keyboard shrinks it
        // fewer rows are loaded (19 went to 8 in iOS run 43495829201). A sent message would get a new id, never a
        // sample one, and sending clears the composer. So: no new message row, and the quote still waits in the field.
        sleep(2)
        XCTAssertEqual(newMessages(app).count, 0, "Quoting must not send anything")
        XCTAssertEqual(field.value as? String, draft, "The quote stays in the composer: nothing sent it")
    }

    @MainActor
    func testSelectTextShowsTheWholeMessage() {
        let app = launch()
        openMenu(on: visibleAnswer(app))
        XCTAssertTrue(app.buttons["Select text"].waitForExistence(timeout: 5))
        app.buttons["Select text"].tap()

        let body = app.descendants(matching: .any).matching(identifier: "message.selectText.body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(body.label.hasPrefix("Answer"), "The sheet should show the message, got: \(body.label)")
        app.buttons["message.selectText.done"].tap()
        XCTAssertFalse(body.waitForExistence(timeout: 2))
    }

    /// Local chats have the same menu. Quote fills the local draft; no message is added and no reply is asked for.
    @MainActor
    func testQuoteInALocalChatFillsTheDraftWithoutSending() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "skip", "-HermesLayout", "compact", "-chatModeDefault", "local",
            "-uiTestLocalExecutor=Test-Model-X",
        ]
        app.launch()
        let newChat = app.buttons.matching(identifier: "shell.newChat").firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 15))
        newChat.tap()
        let field = app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Quote this line")
        app.descendants(matching: .any).matching(identifier: "composer.send").firstMatch.tap()
        let replies = app.descendants(matching: .any).matching(identifier: "local.message.model")
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 20), "The local reply arrives")
        let questions = app.descendants(matching: .any).matching(identifier: "local.message.user")
        let counts = (questions.count, replies.count)

        openMenu(on: questions.firstMatch)
        XCTAssertTrue(app.buttons["Quote in reply"].waitForExistence(timeout: 5))
        app.buttons["Quote in reply"].tap()
        let draft = field.value as? String ?? ""
        XCTAssertTrue(draft.hasPrefix("> Quote this line"), "The draft should start with the quote, got: \(draft)")
        XCTAssertFalse(app.descendants(matching: .any)["local.replying"].waitForExistence(timeout: 3), "No reply asked")
        XCTAssertEqual(questions.count, counts.0, "Quoting must not send anything")
        XCTAssertEqual(replies.count, counts.1)
    }

    /// Memory phase 1: "Remember this" on a local chat's message saves it with Undo, and Settings › On-device › Memory
    /// lists it. Nothing is sent and no reply is asked for.
    @MainActor
    func testRememberThisSavesALocalMessageToMemory() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-HermesOnboarding", "skip", "-HermesLayout", "compact", "-chatModeDefault", "local",
            "-uiTestLocalExecutor=Test-Model-X",
        ]
        app.launch()
        let newChat = app.buttons.matching(identifier: "shell.newChat").firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 15))
        newChat.tap()
        let field = app.descendants(matching: .any).matching(identifier: "composer.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("I grow tomatoes on the balcony")
        app.descendants(matching: .any).matching(identifier: "composer.send").firstMatch.tap()
        let question = app.descendants(matching: .any).matching(identifier: "local.message.user").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 20))

        openMenu(on: question)
        XCTAssertTrue(app.buttons["Remember this"].waitForExistence(timeout: 5))
        app.buttons["Remember this"].tap()
        let saved = app.descendants(matching: .any)["memory.remembered"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Saved to memory, with Undo")

        // Back to the list first (the chat is pushed over the tabs), then the visible copy of the Settings tab, polled
        // while the tab bar settles (TestbedUITestSupport).
        let back = app.buttons["BackButton"]
        if back.waitForExistence(timeout: 5), back.isHittable { back.tap() }
        testbedHittableButton(app, "Settings").tap()
        let memoryLink = app.descendants(matching: .any)["settings.localMemory"]
        for _ in 0..<4 where !memoryLink.exists { app.swipeUp() }
        XCTAssertTrue(memoryLink.waitForExistence(timeout: 5), "Settings › On-device lists Memory")
        memoryLink.tap()
        // A memory row is a button (a tap edits it), so its text is the button's label, not a static text.
        let listed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "I grow tomatoes on the balcony")).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 10), "The memory is listed")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-HermesOnboarding", "skip", "-HermesLayout", "compact", "-HermesSampleChats", "YES"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["transcript"].waitForExistence(timeout: 15))
        return app
    }

    /// The sample chat's last answer that is on screen.
    @MainActor
    private func visibleAnswer(_ app: XCUIApplication) -> XCUIElement {
        for index in stride(from: 24, through: 1, by: -1) {
            let answer = app.descendants(matching: .any)["message.backup-a\(index)"]
            if answer.exists, answer.isHittable { return answer }
        }
        XCTFail("No answer of the sample chat is on screen")
        return app.descendants(matching: .any)["message.backup-a24"]
    }

    /// Message rows that are not the sample chat's own: anything sent during the test.
    @MainActor
    private func newMessages(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'message.' AND NOT (identifier BEGINSWITH 'message.backup-') "
                    + "AND NOT (identifier BEGINSWITH 'message.action.') AND NOT (identifier BEGINSWITH 'message.selectText')"
            ))
    }

    @MainActor
    private func openMenu(on element: XCUIElement) {
        element.press(forDuration: 1.2)
    }
}
