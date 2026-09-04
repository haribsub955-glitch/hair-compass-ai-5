import XCTest

final class TrendRelationshipsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testRelationshipEntrySupportsSideEffectsHealthAndPlanChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TAB", "trends", "HC_MOTION_STATIC"]
        app.launch()
        let explore = app.buttons["exploreRelationships"]
        XCTAssertTrue(explore.waitForExistence(timeout: 15))
        XCTAssertTrue(explore.isHittable)
        capture("Trends relationships entry", app)
        explore.tap()
        let outcome = app.buttons["comparisonOutcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 5))
        outcome.tap()
        app.buttons["Side effects"].tap()
        XCTAssertTrue(app.buttons["comparisonSideEffectType"].exists)
        app.buttons["comparisonContext"].tap()
        app.buttons["Sleep (hours)"].tap()
        capture("Side effects and Apple Health", app)
        app.buttons["Around a change"].tap()
        XCTAssertTrue(app.buttons["comparisonEvent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["eventObservationComparison"].exists)
        capture("Side effects around a plan change", app)
        outcome.tap()
        app.buttons["Shedding"].tap()
        XCTAssertFalse(app.buttons["comparisonSideEffectType"].exists)
        capture("Shedding around a plan change", app)
    }

    @MainActor
    func testPhotoBabyHairHighlightAppearsInTrendsAndCanBeRemoved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TAB", "photos", "HC_MOTION_STATIC", "HC_CAPTURED"]
        app.launch()
        let capturePhoto = app.buttons["Capture progress photo"]
        XCTAssertTrue(capturePhoto.waitForExistence(timeout: 15))
        capturePhoto.tap()
        let observation = app.switches["captureBabyHairs"]
        XCTAssertTrue(observation.waitForExistence(timeout: 6))
        scrollTo(observation, in: app)
        observation.switches.firstMatch.exists ? observation.switches.firstMatch.tap() : observation.tap()
        XCTAssertEqual(observation.value as? String, "1")
        capture("Photo milestone at capture", app)
        let save = app.buttons["Save photo"]
        scrollTo(save, in: app)
        save.tap()
        XCTAssertTrue(app.buttons["tab.trends"].waitForExistence(timeout: 5))
        app.buttons["tab.trends"].tap()
        let filter = app.buttons["trendHighlightFilter"]
        scrollTo(filter, in: app)
        filter.tap()
        app.buttons["Baby hairs"].tap()
        let highlightedPhotos = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Baby hairs noticed"))
        let highlight = highlightedPhotos.firstMatch
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        scrollTo(highlight, in: app)
        capture("Baby hairs highlight in Trends", app)
        let highlightedCount = highlightedPhotos.count
        highlight.tap()
        let edit = app.switches["photoBabyHairs"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        scrollTo(edit, in: app)
        XCTAssertEqual(edit.value as? String, "1")
        edit.switches.firstMatch.exists ? edit.switches.firstMatch.tap() : edit.tap()
        XCTAssertEqual(edit.value as? String, "0")
        capture("Photo milestone can be edited", app)
        app.buttons["Done"].tap()
        XCTAssertEqual(highlightedPhotos.count, highlightedCount - 1)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
