import StoreKitTest
import XCTest

final class OnboardingOfferUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["HC_ONBOARD", "HC_ONBOARD_STEP", "13", "HC_NORITUAL", "HC_NOLOCK"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["onboardContinueFree"].waitForExistence(timeout: 12))
        return app
    }

    @MainActor
    func testPlanPreviewPriceAndFreeHandoff() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["A small place to begin."].exists)
        capture("01 Starting plan", app)
        app.buttons["onboardOfferNext"].tap()
        XCTAssertTrue(app.buttons["onboardReplayPreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Illustration only—not your data or a prediction."].exists)
        XCTAssertTrue(app.staticTexts["A little context, from Wren"].waitForExistence(timeout: 6))
        capture("02 Example record", app)
        app.buttons["onboardOfferNext"].tap()
        XCTAssertTrue(app.buttons["onboardPurchaseMonthly"].waitForExistence(timeout: 12))
        capture("03 Support and plans", app)
        reveal(app.buttons["onboardPurchaseMonthly"], in: app)
        app.buttons["onboardPurchaseMonthly"].tap()
        XCTAssertTrue(app.buttons["onboardPurchaseMonthly"].isSelected)
        XCTAssertFalse(app.buttons["onboardPurchaseYearly"].isSelected)
        XCTAssertTrue(app.buttons["onboardBuySelectedPlan"].exists)
        XCTAssertFalse(app.buttons["onboardOpenPlan"].exists, "Selection alone must never purchase or advance")
        reveal(app.buttons["onboardBuySelectedPlan"], in: app)
        capture("04 Monthly choice and billing", app)
        app.buttons["onboardContinueFree"].tap()
        XCTAssertTrue(app.buttons["onboardOpenPlan"].waitForExistence(timeout: 6))
        capture("05 Ready to begin", app)
        app.buttons["onboardOpenPlan"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["starterPlanSection"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testBackAndReplayNeverBlockContinuing() {
        let app = launch(["HC_OFFER_PHASE", "preview"])
        app.buttons["onboardReplayPreview"].tap()
        XCTAssertTrue(app.buttons["onboardOfferNext"].isEnabled)
        app.buttons["onboardOfferNext"].tap()
        app.buttons["onboardOfferBack"].tap()
        XCTAssertTrue(app.buttons["onboardReplayPreview"].waitForExistence(timeout: 5))
        app.buttons["onboardOfferBack"].tap()
        XCTAssertTrue(app.staticTexts["A small place to begin."].waitForExistence(timeout: 5))
        app.buttons["onboardContinueFree"].tap()
        XCTAssertTrue(app.buttons["onboardOpenPlan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStaticPreviewShowsTheCompleteMeaningImmediately() {
        let app = launch(["HC_OFFER_PHASE", "preview", "HC_MOTION_STATIC"])
        XCTAssertFalse(app.buttons["onboardReplayPreview"].exists)
        XCTAssertTrue(app.staticTexts["A little context, from Wren"].exists)
        XCTAssertTrue(app.buttons["onboardOfferNext"].isHittable)
        capture("06 Reduced-motion equivalent", app)
    }

    @MainActor
    func testBackgroundReturnKeepsTheOfferAndSelection() {
        let app = launch(["HC_OFFER_PHASE", "preview", "HC_MOTION_STATIC"])
        app.buttons["onboardOfferNext"].tap()
        let monthly = app.buttons["onboardPurchaseMonthly"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 12))
        reveal(monthly, in: app)
        monthly.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(monthly.waitForExistence(timeout: 8))
        XCTAssertTrue(monthly.isSelected)
        XCTAssertTrue(app.buttons["onboardContinueFree"].isHittable)
    }

    @MainActor
    func testActiveProDoesNotSellAnotherSubscription() {
        let app = launch(["HC_OFFER_PHASE", "pricing", "HC_PRO", "HC_MOTION_STATIC"])
        XCTAssertTrue(app.descendants(matching: .any)["onboardProActive"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboardBuySelectedPlan"].exists)
        XCTAssertFalse(app.buttons["onboardPurchaseYearly"].exists)
        XCTAssertEqual(app.buttons["onboardContinueFree"].label, "Continue to my plan")
    }

    @MainActor
    func testLargeTypeKeepsFreeExitAndBillingReachable() {
        let app = launch(["HC_OFFER_PHASE", "pricing", "HC_MOTION_STATIC",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["onboardContinueFree"].isHittable)
        XCTAssertTrue(app.buttons["onboardPurchaseYearly"].waitForExistence(timeout: 12))
        reveal(app.buttons["onboardBuySelectedPlan"], in: app, attempts: 12)
        XCTAssertTrue(app.buttons["onboardBuySelectedPlan"].isHittable)
        capture("07 Accessibility text pricing", app)
        app.buttons["onboardContinueFree"].tap()
        XCTAssertTrue(app.buttons["onboardOpenPlan"].waitForExistence(timeout: 5))
    }

    /// Local StoreKit only: no Apple Account is charged by these tests.
    @MainActor
    func testVerifiedPurchaseAdvancesToTheSameFinale() throws {
        try requireLocalStoreKitUI()
        let session = try storeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let app = launch(["HC_OFFER_PHASE", "pricing", "HC_MOTION_STATIC"])
        let buy = app.buttons["onboardBuySelectedPlan"]
        XCTAssertTrue(buy.waitForExistence(timeout: 12))
        reveal(buy, in: app)
        buy.tap()
        XCTAssertTrue(app.buttons["onboardOpenPlan"].waitForExistence(timeout: 15))
        XCTAssertTrue(session.allTransactions().contains { $0.productIdentifier == "com.harib.haircompass.pro.yearly2" })
    }

    @MainActor
    func testCancelledPurchaseKeepsTheFreeExit() async throws {
        try requireLocalStoreKitUI()
        let session = try storeSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: StoreKitPurchaseAPI())
        let app = launch(["HC_OFFER_PHASE", "pricing", "HC_MOTION_STATIC"])
        let buy = app.buttons["onboardBuySelectedPlan"]
        XCTAssertTrue(buy.waitForExistence(timeout: 12))
        reveal(buy, in: app)
        buy.tap()
        let free = app.buttons["onboardContinueFree"]
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: free)
        await fulfillment(of: [available], timeout: 10)
        XCTAssertFalse(app.buttons["onboardOpenPlan"].exists)
        free.tap()
        XCTAssertTrue(app.buttons["onboardOpenPlan"].waitForExistence(timeout: 5))
    }

    /// The command-line UI runner on some simulator versions does not attach the scheme's
    /// local store to the app under test (a sandbox Apple Account prompt appears instead).
    /// Keep these end-to-end checks explicit/opt-in. App-hosted service tests also need a
    /// confirmed local store; they are not a fallback for account authentication. Never enter an Apple ID here.
    private func requireLocalStoreKitUI() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HC_UI_STOREKIT_TESTING"] == "1",
                          "Requires a confirmed local StoreKit session attached to the UI-tested app. Set HC_UI_STOREKIT_TESTING=1 only in that environment; never use an Apple Account to satisfy this test.")
    }

    @MainActor
    private func storeSession() throws -> SKTestSession {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HairCompass.storekit")
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 6) {
        for _ in 0..<attempts {
            if element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
