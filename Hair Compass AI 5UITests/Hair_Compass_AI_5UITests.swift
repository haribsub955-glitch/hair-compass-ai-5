import XCTest

final class Hair_Compass_AI_5UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Plan leads with a time-based evidence path, and each checkpoint explains what it can and
    /// cannot tell the person yet.
    @MainActor
    func testEvidencePathShowsOnPlan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_TAB", "care", "HC_MOTION_STATIC"]
        app.launch()

        let path = app.otherElements["evidencePath"]
        XCTAssertTrue(path.waitForExistence(timeout: 10), "the evidence path should lead the Plan screen")
        let week4 = app.buttons["evidenceMilestone.4"]
        XCTAssertTrue(week4.waitForExistence(timeout: 4))
        week4.tap()
        XCTAssertTrue(app.descendants(matching: .any)["evidenceMilestoneDetail.4"].waitForExistence(timeout: 4))
        XCTAssertEqual(week4.value as? String, "Expanded")
        XCTAssertTrue(app.descendants(matching: .any)["planStrands"].exists)
    }

    /// "I'm worried" starts with a bounded picker rather than a blank chat, answers in four
    /// ordered sections, and lets that concern shape today's grounding note.
    @MainActor
    func testWorriedFlowAnswersInFourSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_MOTION_STATIC"]
        app.launch()

        let worried = app.buttons["groundingWorried"]
        XCTAssertTrue(worried.waitForExistence(timeout: 10), "the grounding card should offer I'm worried")
        worried.tap()

        let option = app.buttons["concernOption.moreShedding"]
        XCTAssertTrue(option.waitForExistence(timeout: 4), "the bounded picker should list shedding")
        option.tap()
        XCTAssertTrue(app.descendants(matching: .any)["concernResponse"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["What the record shows"].exists)
        XCTAssertTrue(app.staticTexts["What cannot be concluded yet"].exists)
        XCTAssertTrue(app.staticTexts["What to do next"].exists)

        let done = app.buttons["concernDone"]
        for _ in 0..<3 where !done.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["When to seek help"].exists)
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(
            app.staticTexts["Let's separate one moment from the pattern"].waitForExistence(timeout: 5),
            "today's note should answer the concern after the flow closes"
        )
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
        // HC_AI_CLOUD_OFF: with the cloud key configured the paywall has nothing to disclose (the
        // AI features run on every iPhone), so this asserts the no-cloud build's contract.
        app.launchArguments = ["HC_ONBOARD", "HC_ONBOARD_STEP", "13", "HC_AI_STATUS", "notEnabled", "HC_AI_CLOUD_OFF",
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

    /// "Erase everything and start over" wipes the record and returns to the illustrated cover,
    /// exactly as a first install would — and it survives the confirmation alert.
    /// This test wipes the simulator's app data by design — that is the feature under test.
    /// Later tests re-seed their own state via `HC_SEED_DEMO` on launch, so this is safe to run
    /// ahead of them.
    @MainActor
    func testEraseReturnsToOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_PROFILE"]
        app.launch()

        let erase = app.buttons["eraseStartOver"]
        XCTAssertTrue(erase.waitForExistence(timeout: 10), "the destructive row must exist on Profile")
        erase.tap()

        let confirm = app.alerts.buttons["Erase"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6), "erase must ask first")
        confirm.tap()

        XCTAssertTrue(app.buttons["onboardIntroPrimary"].waitForExistence(timeout: 12),
                      "after the wipe the app must open on the illustrated cover")
    }

    /// The finale's promise is "Open my plan": after onboarding (and the tour that follows), the
    /// person is on the Plan tab with the starting plan on screen.
    @MainActor
    func testOpenMyPlanLandsOnThePlanTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD", "HC_ONBOARD_STEP", "14", "HC_NORITUAL"]
        app.launch()
        let open = app.buttons["onboardOpenPlan"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the finale must offer Open my plan")
        open.tap()
        XCTAssertTrue(app.otherElements["starterPlanSection"].waitForExistence(timeout: 10)
                      || app.staticTexts["Your starting plan"].waitForExistence(timeout: 2),
                      "after Open my plan the Plan tab with the starting plan must be showing")
    }

    /// A quiet day is one tap: with yesterday logged and today empty, "Same as yesterday" exists
    /// and turns into "Edit log" once tapped.
    @MainActor
    func testSameAsYesterdayLogsToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_NOTODAY"]
        app.launch()
        let chip = app.buttons["sameAsYesterday"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "today is empty and yesterday exists — the chip must show")
        chip.tap()
        XCTAssertTrue(app.buttons["Edit log"].waitForExistence(timeout: 6), "one tap must produce today's log")
        XCTAssertFalse(chip.exists, "the chip retires once today is logged")
    }

    /// A plan action is one tap and one Undo; Skip lives behind a long press and asks for a
    /// reason; the closure line stays away while rows are open.
    @MainActor
    func testPlanRowCompletesUndoesAndSkips() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL", "HC_PLANOPEN"]
        app.launch()

        let circle = app.buttons["planRowComplete.0"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10), "today's plan must list an open action")
        XCTAssertEqual(circle.value as? String, "Not yet")
        XCTAssertFalse(app.otherElements["planClosure"].exists, "the closure line waits for every row")

        circle.tap()
        let undo = app.buttons["planRowUndo.0"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "a completed row offers Undo")
        XCTAssertTrue((circle.value as? String)?.hasPrefix("Completed") == true)

        undo.tap()
        XCTAssertTrue(circle.waitForExistence(timeout: 4))
        XCTAssertTrue(waitFor(circle, value: "Not yet", timeout: 4),
                      "Undo must restore the open row after SwiftData publishes the deletion")

        // Skip lives behind a long press on the row and asks for a reason.
        app.otherElements["planRow.0"].press(forDuration: 1.2)
        let skip = app.buttons["Skip today"]
        XCTAssertTrue(skip.waitForExistence(timeout: 4), "the long-press menu offers Skip today")
        skip.tap()
        let reason = app.buttons["Forgot"]
        XCTAssertTrue(reason.waitForExistence(timeout: 4), "skipping asks for a reason")
        reason.tap()
        XCTAssertTrue(waitFor(circle, value: "Skipped", timeout: 4), "the row settles as Skipped once the reason is recorded")
    }

    /// Today opens on the horizon and one grounding card; "Why this?" reveals the reason.
    @MainActor
    func testGroundingCardExplainsItself() throws {
        let app = XCUIApplication()
        app.launchArguments = ["HC_SEED_DEMO", "HC_NORITUAL"]
        app.launch()
        XCTAssertTrue(app.otherElements["calmHorizon"].waitForExistence(timeout: 10), "the horizon header leads the page")
        let card = app.otherElements["groundingCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 4), "one grounding card follows it")
        XCTAssertTrue(app.otherElements["evidenceRibbon"].exists)
        app.buttons["groundingWhy"].tap()
        XCTAssertTrue(app.staticTexts["groundingReason"].waitForExistence(timeout: 4), "Why this? shows the reason")
        XCTAssertFalse(app.buttons["tutorialSkip"].exists, "the card tour is gone")
        XCTAssertFalse(app.buttons["Skip the tour"].exists, "the card tour is gone")

        // Important 8: the headerless shedding scene should close its gap — a scrolled
        // screenshot for a human look, since "no blank band above TODAY'S SHEDDING" is a
        // visual claim no assertion can make on its own.
        app.swipeUp()
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = "g2-shedding-scene"
        add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-haribazri-Hair-Compass-AI-5/ff0a543b-cd29-4e99-83c4-0d3dc9b8f4cb/scratchpad/g2-shedding-scene.png"))
    }

    /// Polls an element's accessibility `value` rather than sleeping a fixed amount — the write
    /// behind a confirmation-dialog action lands a beat after the dialog itself dismisses.
    @MainActor
    private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { _, _ in (element.value as? String) == value }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
