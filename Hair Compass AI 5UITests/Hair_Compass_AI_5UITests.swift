import XCTest

final class Hair_Compass_AI_5UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// First run presents the cinematic onboarding: welcome → name step.
    @MainActor
    func testOnboardingFirstRunReachesNameStep() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD"]
        app.launch()

        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 8))
        begin.tap()

        // Second screen collects the name.
        XCTAssertTrue(app.textFields["onboardName"].waitForExistence(timeout: 6))
    }

    /// The profile (Baseline) can replay the onboarding, and the replay can be closed again.
    @MainActor
    func testProfileCanReplayOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_PROFILE"]   // onboarded demo profile + open the profile sheet
        app.launch()

        let replay = app.buttons["replayOnboarding"]
        XCTAssertTrue(replay.waitForExistence(timeout: 8))
        replay.tap()

        // The animated walkthrough opens on its welcome screen.
        XCTAssertTrue(app.buttons["Begin"].waitForExistence(timeout: 6))

        // A replay can be exited early via the close button, returning to the profile.
        app.buttons["Close walkthrough"].tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 6))
    }

    /// A launch ritual must always be skippable and never gate the app.
    ///
    /// Forces "knot" specifically: it's interaction-paced (`estimatedDuration == nil`, only
    /// completes once traced), so — unlike "comb"/"massage", which self-complete in ~1s by design
    /// (see CombRitual's doc comment) and would race their own dismissal against this test's tap —
    /// it stays on screen until skipped, giving a deterministic target for the skip assertion.
    @MainActor
    func testLaunchRitualIsSkippable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_RITUAL_KIND", "knot"]   // force a ritual on launch
        app.launch()

        let skip = app.buttons["ritualSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()

        // Skipping reveals the normal app (Today tab bar) underneath.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
