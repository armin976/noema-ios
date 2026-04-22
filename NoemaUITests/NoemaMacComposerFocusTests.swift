import XCTest

final class NoemaMacComposerFocusTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testComposerRetainsFocusAcrossContinuousTyping() throws {
        let app = XCUIApplication()
        app.launch()

        dismissOnboardingIfPresent(in: app)

        let composer = composerElement(in: app)
        XCTAssertTrue(composer.waitForExistence(timeout: 12), "Composer did not appear")

        composer.click()
        composer.typeText("hello")

        XCTAssertTrue(
            composerValue(of: composer).contains("hello"),
            "Composer did not retain the first typing sequence"
        )

        composer.typeText(" world")

        XCTAssertTrue(
            composerValue(of: composer).contains("hello world"),
            "Composer lost focus before completing the second typing sequence"
        )
    }

    private func dismissOnboardingIfPresent(in app: XCUIApplication) {
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 4) {
            getStarted.click()
        }
    }

    private func composerElement(in app: XCUIApplication) -> XCUIElement {
        let candidates = [
            app.textViews["message-input"],
            app.textViews["Message input"],
            app.textAreas["message-input"],
            app.textAreas["Message input"],
        ]

        if let existing = candidates.first(where: \.exists) {
            return existing
        }

        return candidates[0]
    }

    private func composerValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }
}
