import XCTest

final class ChatSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDebugChatStreamsMockResponse() {
        let app = XCUIApplication()
        app.launchArguments += ["CHAT_SMOKE_FAKE", "CHAT_SMOKE_AUTO"]
        app.launch()

        if app.buttons["Close"].waitForExistence(timeout: 1) {
            app.buttons["Close"].tap()
        }

        let debugMenu = app.menuBars.menuBarItems["Debug"]
        if debugMenu.waitForExistence(timeout: 2) {
            debugMenu.click()
            let openChat = debugMenu.menuItems["Open Chat Screen"]
            if openChat.waitForExistence(timeout: 2) {
                openChat.click()
            }
        }

        let prompt = app.textFields["ChatPromptField"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Ping")

        let send = app.buttons["ChatSendButton"]
        if send.exists {
            send.tap()
        }

        let status = app.staticTexts["ChatStatusLabel"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        let assistant = app.staticTexts["AssistantMessage"]
        let expectation = expectation(for: NSPredicate(format: "label CONTAINS %@", "Mock answer"), evaluatedWith: assistant, handler: nil)
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(assistant.label.contains("Ping"))
    }
}
