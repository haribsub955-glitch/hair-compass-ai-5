import XCTest

/// StoreKit-fixture probes for the App Review demo recording. The simulator cannot reach the
/// real sandbox catalog, and launches outside the test infrastructure do not reliably attach
/// the scheme's StoreKit configuration — `xcodebuild test` injects it itself. Both tests skip
/// unless explicitly armed via environment, so the normal suite never pays for them.
final class DemoRecordingTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Fast probe: jump straight to the paywall and require a real fixture price on screen.
    func testPaywallShowsFixturePrices() throws {
        guard ProcessInfo.processInfo.environment["HC_DEMO_PROBE"] == "1" else {
            throw XCTSkip("Demo-only probe; set TEST_RUNNER_HC_DEMO_PROBE=1 to run.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["HC_NORITUAL", "HC_ONBOARD_STEP", "13", "HC_PAYWALL_BOTTOM"]
        app.launch()
        let price = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '9.99'")).firstMatch
        XCTAssertTrue(price.waitForExistence(timeout: 30),
                      "No fixture price appeared on the paywall")
    }

    /// Holds a clean, argument-free launch open so a human can drive the demo while the
    /// screen recorder runs; the injected StoreKit configuration stays live for the purchase.
    func testHoldForDemoRecording() throws {
        guard let minutes = ProcessInfo.processInfo.environment["HC_DEMO_HOLD_MINUTES"]
            .flatMap(Double.init) else {
            throw XCTSkip("Demo-only hold; set TEST_RUNNER_HC_DEMO_HOLD_MINUTES to run.")
        }
        let app = XCUIApplication()
        app.launch()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: minutes * 60))
    }
}
