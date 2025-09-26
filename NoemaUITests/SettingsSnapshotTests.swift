import XCTest

final class SettingsSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsAndAdvancedSnapshots() throws {
        let app = XCUIApplication()
        app.launchArguments += baseLaunchArguments()
        app.launch()

        openSettings(app)
        attachScreenshot(app.screenshot(), named: "Settings-Basic")

        let advancedButton = app.navigationBars.buttons["Advanced settings"]
        XCTAssertTrue(advancedButton.waitForExistence(timeout: 3))
        advancedButton.tap()

        let advancedSheet = app.navigationBars["Advanced"]
        XCTAssertTrue(advancedSheet.waitForExistence(timeout: 3))
        attachScreenshot(app.screenshot(), named: "Settings-Advanced")
    }

    func testSettingsSnapshotXXLType() throws {
        let app = XCUIApplication()
        app.launchArguments += baseLaunchArguments()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()

        openSettings(app)
        attachScreenshot(app.screenshot(), named: "Settings-Basic-XXL")
    }

    private func baseLaunchArguments() -> [String] {
        [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-hasCompletedOnboarding", "YES"
        ]
    }

    private func openSettings(_ app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15))
        settingsTab.tap()
        let navBar = app.navigationBars["Settings"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
