import XCTest

final class Hair_Compass_AI_5UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBaselineRequiresNameThenReachesToday() throws {
        let app = XCUIApplication()
        app.launch()

        // Fresh launch shows the one-time baseline flow.
        let nameField = app.textFields["baselineName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 6))

        // Save is disabled until a name is entered.
        let save = app.buttons["baselineSave"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)

        nameField.tap()
        nameField.typeText("Ari")

        // Pick a condition so the baseline is meaningful.
        app.buttons["condition_androgenetic"].tap()

        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Lands on the Today tab of the main app.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Trends"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
