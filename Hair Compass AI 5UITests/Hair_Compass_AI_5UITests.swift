import XCTest

final class Hair_Compass_AI_5UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// First run presents the illustrated cover (`OnboardingIntro`, which replaced the old single
    /// "Begin" welcome step), and walking it through hands off to the name step.
    @MainActor
    func testOnboardingFirstRunReachesNameStep() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD"]
        app.launch()

        let primary = app.buttons["onboardIntroPrimary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "first run should open on the illustrated cover")

        // Walk the cover to its end — "Continue" on each page, "Set up my compass" on the last.
        // Bounded rather than a fixed four taps so adding a page doesn't break the test.
        let name = app.textFields["onboardName"]
        for _ in 0..<8 {
            if name.exists { break }
            guard primary.waitForExistence(timeout: 4) else { break }
            primary.tap()
        }

        XCTAssertTrue(name.waitForExistence(timeout: 6), "the cover should hand off to the name step")
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

        // The walkthrough opens on the illustrated cover's first page.
        XCTAssertTrue(app.buttons["onboardIntroPrimary"].waitForExistence(timeout: 6))

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

    // MARK: - Paywall AI disclosure (App Review 2.1 + 3.1.2 lineage; 1.1 contract)

    /// With Apple Intelligence merely switched OFF, the paywall must disclose that above the
    /// price — and must STILL offer the purchase buttons: since 1.1 Pro carries
    /// device-independent value (check-ins, trends, labs, photos), so the sale is never
    /// withdrawn. The free path stays.
    @MainActor
    func testPaywallDisclosesAINotEnabledAndStillSells() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD", "HC_ONBOARD_STEP", "13", "HC_AI_STATUS", "notEnabled",
                               "HC_PAYWALL_BOTTOM", "HC_NORITUAL"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["proAvailabilityNotice"].waitForExistence(timeout: 10),
                      "the availability notice must say the AI half is off before the buttons sell it")
        XCTAssertTrue(app.buttons["onboardContinueFree"].waitForExistence(timeout: 6),
                      "the free path must remain the forward move")
        XCTAssertTrue(app.buttons["onboardPurchaseYearly"].waitForExistence(timeout: 12),
                      "yearly must still be purchasable — Pro's non-AI half works on every iPhone")
        XCTAssertTrue(app.buttons["onboardPurchaseMonthly"].exists,
                      "monthly must still be purchasable — Pro's non-AI half works on every iPhone")
    }

    /// Same screen with the model available: the purchase buttons must be offered (products come
    /// from the scheme's StoreKit configuration). Guards against over-correcting into a paywall
    /// that never sells.
    @MainActor
    func testPaywallOffersPurchaseWhenAIAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD", "HC_ONBOARD_STEP", "13", "HC_AI_STATUS", "available",
                               "HC_PAYWALL_BOTTOM", "HC_NORITUAL"]
        app.launch()

        XCTAssertTrue(app.buttons["onboardPurchaseYearly"].waitForExistence(timeout: 12),
                      "yearly must be purchasable when the model is available")
        XCTAssertTrue(app.buttons["onboardPurchaseMonthly"].exists,
                      "monthly must be purchasable when the model is available")
        XCTAssertFalse(app.descendants(matching: .any)["proAvailabilityNotice"].exists,
                       "no availability warning when the model is available")
    }
}
