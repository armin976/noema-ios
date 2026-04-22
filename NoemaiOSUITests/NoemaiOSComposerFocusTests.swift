import XCTest

final class NoemaiOSComposerFocusTests: XCTestCase {
    private enum SendBehavior: String {
        case keyboardToolbarSend = "keyboard_toolbar_send"
        case returnKeySends = "return_key_sends"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testComposerAcceptsTypingAfterSingleTap() throws {
        let app = configuredApp(fakeChatReady: true)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        composer.typeText("hello")

        XCTAssertTrue(
            composerValue(of: composer).contains("hello"),
            "Composer did not accept text entry immediately after the first tap"
        )
    }

    func testComposerShowsModelAlertWhenUnavailable() throws {
        let app = configuredApp(fakeChatReady: false)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let modelAlert = app.alerts["Load a model to chat"]
        XCTAssertTrue(modelAlert.waitForExistence(timeout: 5), "Expected the model-required alert to appear")
    }

    func testMoreActionsTrayExposesNamedAttachmentControls() throws {
        let app = configuredApp(fakeChatReady: true, forceImageInput: true)
        app.launch()

        let moreActionsButton = app.buttons["chat-more-actions-button"]
        XCTAssertTrue(waitForHittable(moreActionsButton, timeout: 12), "More Actions button did not become tappable")

        moreActionsButton.tap()

        let tray = app.otherElements["chat-attachment-tray"]
        XCTAssertTrue(tray.waitForExistence(timeout: 5), "Attachment tray did not appear")

        XCTAssertTrue(app.buttons["chat-attachments-all-photos"].waitForExistence(timeout: 2), "All Photos button did not appear")
        XCTAssertTrue(app.buttons["chat-attachments-camera"].waitForExistence(timeout: 2), "Take Photo button did not appear")
        XCTAssertTrue(app.buttons["chat-tool-web-search"].waitForExistence(timeout: 2), "Web Search row did not appear")
        XCTAssertTrue(app.buttons["chat-tool-python"].waitForExistence(timeout: 2), "Python row did not appear")
        XCTAssertFalse(app.buttons["Drag"].exists, "Unexpected Drag button appeared in the attachment tray")
    }

    func testReturnInsertModeKeepsReturnAsNewLine() throws {
        let app = configuredApp(fakeChatReady: true, sendBehavior: .keyboardToolbarSend)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.tap()
        composer.typeText("hello")
        composer.typeText("\n")
        composer.typeText("world")

        XCTAssertTrue(
            composerValue(of: composer).contains("hello\nworld"),
            "Return should insert a newline when return-send mode is off"
        )
    }

    func testReturnKeySendModeSubmitsOnReturn() throws {
        let app = configuredApp(fakeChatReady: true, sendBehavior: .returnKeySends)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.tap()
        composer.typeText("hello")

        composer.typeText("\n")
        XCTAssertTrue(waitForComposerValueToExclude("hello", composer: composer, timeout: 5), "Return key did not submit in return-key-send mode")
    }

    func testCommandReturnSubmitsWhenKeyboardShortcutIsEnabled() throws {
        let app = configuredApp(fakeChatReady: true, sendBehavior: .keyboardToolbarSend)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.tap()
        composer.typeText("hello")
        composer.typeKey(.return, modifierFlags: .command)

        XCTAssertTrue(waitForComposerValueToExclude("hello", composer: composer, timeout: 5), "Command-Return did not submit the composer")
    }

    func testNoKeyboardAccessorySendButtonAppears() throws {
        let app = configuredApp(fakeChatReady: true, sendBehavior: .keyboardToolbarSend)
        app.launch()

        let composer = composerElement(in: app)
        XCTAssertTrue(waitForHittable(composer, timeout: 12), "Composer did not become tappable")

        composer.tap()
        XCTAssertFalse(app.toolbars.buttons["Send"].exists, "Keyboard accessory Send button should not appear")
        XCTAssertFalse(app.keyboards.buttons["Send"].exists, "Keyboard accessory Send button should not appear")
    }

    private func configuredApp(
        fakeChatReady: Bool,
        forceImageInput: Bool = false,
        sendBehavior: SendBehavior = .keyboardToolbarSend
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launchEnvironment["UITEST_CHAT_SEND_BEHAVIOR"] = sendBehavior.rawValue
        if fakeChatReady {
            app.launchEnvironment["UITEST_FAKE_CHAT_READY"] = "1"
        }
        if forceImageInput {
            app.launchEnvironment["UITEST_FORCE_IMAGE_INPUT"] = "1"
        }
        return app
    }

    private func composerElement(in app: XCUIApplication) -> XCUIElement {
        let candidates = [
            app.textViews["message-input"],
            app.textViews["Message input"],
            app.descendants(matching: .textView)["message-input"],
            app.descendants(matching: .textView)["Message input"],
        ]

        if let existing = candidates.first(where: { $0.exists }) {
            return existing
        }

        return candidates[0]
    }

    private func composerValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func waitForComposerValueToExclude(_ text: String, composer: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { _, _ in
            let value = composer.value as? String ?? ""
            return !value.contains(text)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: composer)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
