import XCTest

final class LivingClinicalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// One end-to-end smoke test for the additive migration. It verifies the new orientation
    /// surfaces while moving through the unchanged five-tab shell.
    @MainActor
    func testPlanLabsAndTrendsKeepTheirEvidenceAnchors() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TAB", "care", "HC_MOTION_STATIC"]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["evidenceHorizon"].waitForExistence(timeout: 10),
            "Plan should orient the person on the existing evidence clock"
        )
        capture("Plan journal", app: app)

        app.buttons["tab.labs"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["labLatestSummary"].waitForExistence(timeout: 6),
            "Labs should summarize the latest saved ranges before the ledger"
        )
        XCTAssertTrue(app.descendants(matching: .any)["labResultsLedger"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["labsJournalHero"].exists)
        capture("Lab journal", app: app)

        app.buttons["tab.trends"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trendsEvidenceHorizon"].waitForExistence(timeout: 6),
            "Trends should keep the treatment clock visible while the visual baseline develops"
        )
        XCTAssertTrue(app.descendants(matching: .any)["trendsJournalChart"].exists)
        capture("Trends overview", app: app)
        app.swipeUp()
        capture("Trends chart", app: app)

        app.buttons["tab.photos"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["photosJournalHero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Capture progress photo"].exists)
        capture("Photo journal", app: app)

        app.buttons["tab.today"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["todayJournalHero"].waitForExistence(timeout: 5))
        capture("Today check-in first", app: app)
    }

    /// Both first logging and editing stay above the fold; moving the scene must not break
    /// the original log sheet or the one-tap copy path.
    @MainActor
    func testTodayCheckInIsVisibleWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NOTODAY", "HC_NORITUAL", "HC_TAB", "today", "HC_MOTION_STATIC"]
        app.launch()

        let action = app.buttons["dailyCheckInAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, "Log today")
        XCTAssertTrue(action.isHittable, "Daily logging should be reachable without scrolling")
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        XCTAssertLessThan(action.frame.maxY, app.buttons["tab.today"].frame.minY)
        let section = app.descendants(matching: .any)["dailyCheckInSection"].firstMatch
        let horizon = app.descendants(matching: .any)["todayJournalHero"].firstMatch
        XCTAssertLessThan(section.frame.minY, horizon.frame.minY)
        capture("Today ready to check in", app: app)

        action.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let copy = app.buttons["sameAsYesterday"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertTrue(app.buttons["Edit log"].waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable, "Editing should remain in the same top-of-page location")
        XCTAssertFalse(copy.exists)
        capture("Today check-in recorded", app: app)
        action.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testRitualCompletionCanBeUndoneAndVisitPrepOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TAB", "care", "HC_MOTION_STATIC"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["evidenceHorizon"].waitForExistence(timeout: 10))
        let completion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "routineComplete.")).firstMatch
        for _ in 0..<4 where !completion.isHittable { app.swipeUp() }
        XCTAssertTrue(completion.isHittable, app.debugDescription)
        let original = completion.value as? String
        let opposite = original == "Logged" ? "Not logged" : "Logged"
        completion.tap()
        XCTAssertTrue(waitForValue(opposite, on: completion))
        completion.tap()
        XCTAssertTrue(waitForValue(original ?? "Not logged", on: completion))

        app.buttons["tab.labs"].tap()
        let visit = app.buttons["labsVisitPrep"]
        for _ in 0..<7 where !visit.isHittable { app.swipeUp() }
        XCTAssertTrue(visit.isHittable, app.debugDescription)
        visit.tap()
        XCTAssertTrue(app.buttons["Share summary"].waitForExistence(timeout: 6))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["tab.photos"].waitForExistence(timeout: 5))
    }

    private func waitForValue(_ value: String, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)], timeout: 5) == .completed
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
