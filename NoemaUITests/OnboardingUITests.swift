import XCTest

final class OnboardingUITests: XCTestCase {
    func testQuickStartFlowCompletes() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_QUICKSTART_MOCK"] = "1"
        app.launch()

        let menuBar = app.menuBars["Menu Bar"]
        let debugMenu = menuBar.menuItems["Debug"]
        XCTAssertTrue(debugMenu.waitForExistence(timeout: 5), "Debug menu should exist")
        debugMenu.tap()

        let quickStartCommand = debugMenu.menuItems["Quick Start Setup"]
        XCTAssertTrue(quickStartCommand.waitForExistence(timeout: 2), "Quick Start command should appear")
        quickStartCommand.tap()

        let quickStartSheet = app.otherElements["quickstart.sheet"]
        XCTAssertTrue(quickStartSheet.waitForExistence(timeout: 5), "Quick Start sheet should be presented")

        let presetPicker = quickStartSheet.pickers["quickstart.presetPicker"]
        XCTAssertTrue(presetPicker.waitForExistence(timeout: 2))

        let etaText = quickStartSheet.staticTexts["quickstart.eta"]
        XCTAssertTrue(etaText.waitForExistence(timeout: 2))

        let privacySwitch = quickStartSheet.switches["quickstart.privacyToggle"]
        if privacySwitch.exists, (privacySwitch.value as? String) == "0" {
            privacySwitch.tap()
        }

        let installButton = quickStartSheet.buttons["quickstart.install"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 2))
        installButton.tap()

        let statusLabel = quickStartSheet.staticTexts["quickstart.status"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5))
        let readyPredicate = NSPredicate(format: "label CONTAINS %@", "Model ready")
        expectation(for: readyPredicate, evaluatedWith: statusLabel)
        waitForExpectations(timeout: 5)

        let importButton = quickStartSheet.buttons["quickstart.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 2))
        importButton.tap()

        let sampleLabel = quickStartSheet.staticTexts["quickstart.sampleLabel"]
        XCTAssertTrue(sampleLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(sampleLabel.label.contains("sample.csv"))

        let finishButton = quickStartSheet.buttons["quickstart.finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2))
        finishButton.tap()

        XCTAssertFalse(quickStartSheet.waitForExistence(timeout: 2))
    }
}
