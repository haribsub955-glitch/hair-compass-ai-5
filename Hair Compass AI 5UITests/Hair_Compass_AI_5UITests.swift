import XCTest

final class Hair_Compass_AI_5UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingNameIsRequiredBeforeAdvancing() throws {
        let app = launchForOnboarding()

        XCTAssertTrue(app.buttons["onboardingNextButton"].waitForExistence(timeout: 5))

        // Welcome splash -> aboutYou (name + age + sex combined)
        tapPrimaryProgressButton(in: app)

        let nameField = app.textFields["onboardingNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        // Try to advance without filling name — should stay on same screen
        tapPrimaryProgressButton(in: app)
        XCTAssertTrue(nameField.exists)

        // Fill name, age, sex then advance to texture selection
        fillAboutYouStep(in: app, name: "Ari")
        tapPrimaryProgressButton(in: app)
        // Should now be on texture selection step
        XCTAssertTrue(app.staticTexts["What's your hair texture?"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testOnboardingShowsConditionalPatchStepForAlopeciaAreata() throws {
        let app = launchForOnboarding()
        XCTAssertTrue(app.buttons["onboardingNextButton"].waitForExistence(timeout: 5))

        // Welcome splash -> aboutYou
        tapPrimaryProgressButton(in: app)

        let nameField = app.textFields["onboardingNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        fillAboutYouStep(in: app, name: "Ari")
        tapPrimaryProgressButton(in: app)

        // Texture + goal (defaults exist, just move ahead)
        tapPrimaryProgressButton(in: app)
        tapPrimaryProgressButton(in: app)

        // Hair loss focus — select alopecia areata
        let areataChoice = app.buttons["onboardingChoice_alopecia_areata"]
        XCTAssertTrue(areataChoice.waitForExistence(timeout: 4))
        areataChoice.tap()
        tapPrimaryProgressButton(in: app)

        // Hair loss duration
        app.buttons["3–6 months"].tap()
        tapPrimaryProgressButton(in: app)

        // Pattern & history (combined screen) — both fields are required to
        // enable Next (pattern ≥ 3 chars, family history ≥ 2 chars).
        let patternField = app.textFields["onboardingPatternField"]
        XCTAssertTrue(patternField.waitForExistence(timeout: 4))
        typeIfNeeded(patternField, text: "temples and part line")

        let familyField = app.textFields["onboardingFamilyHistoryField"]
        XCTAssertTrue(familyField.waitForExistence(timeout: 4))
        typeIfNeeded(familyField, text: "mother")
        tapPrimaryProgressButton(in: app)

        // Should now show conditional patch step
        XCTAssertTrue(app.textFields["onboardingPatchAreaField"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testOnboardingCanCompleteAndReturnToDashboard() throws {
        let app = launchForOnboarding()
        XCTAssertTrue(app.buttons["onboardingNextButton"].waitForExistence(timeout: 5))

        // Step through onboarding with required fields filled.
        for _ in 0..<30 {
            if app.buttons["Create Plan"].exists && app.buttons["Create Plan"].isEnabled {
                app.buttons["Create Plan"].tap()
                break
            }

            if app.textFields["onboardingNameField"].exists {
                typeIfNeeded(app.textFields["onboardingNameField"], text: "Ari")
            }

            dismissKeyboardIfVisible(in: app)
            _ = tapOption("26–35", in: app)
            _ = tapOption("Female", in: app)
            if app.buttons["3–6 months"].exists { app.buttons["3–6 months"].tap() }

            if app.buttons["onboardingChoice_not_sure_yet"].exists {
                app.buttons["onboardingChoice_not_sure_yet"].tap()
            }

            // Pattern and family history are required to advance step 7;
            // patch area is required only on the alopecia-areata branch.
            if app.textFields["onboardingPatternField"].exists {
                typeIfNeeded(app.textFields["onboardingPatternField"], text: "temples")
            }

            if app.textFields["onboardingFamilyHistoryField"].exists {
                typeIfNeeded(app.textFields["onboardingFamilyHistoryField"], text: "none known")
            }

            if app.textFields["onboardingPatchAreaField"].exists {
                typeIfNeeded(app.textFields["onboardingPatchAreaField"], text: "scalp")
            }

            tapPrimaryProgressButton(in: app)
        }

        // The app uses a custom floating tab bar (no UITabBar); "Today" is its
        // first tab and only exists once onboarding has been dismissed.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 6))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func launchForOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "UITEST_FORCE_ONBOARDING",
            "UITEST_RESET_PROFILE",
            "UITEST_REQUIRE_EMPTY_FIELDS"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func tapPrimaryProgressButton(in app: XCUIApplication) {
        if app.buttons["Create Plan"].exists && app.buttons["Create Plan"].isHittable {
            app.buttons["Create Plan"].tap()
            return
        }
        if app.buttons["Next"].exists && app.buttons["Next"].isHittable {
            app.buttons["Next"].tap()
            return
        }
        if app.buttons["Continue"].exists && app.buttons["Continue"].isHittable {
            app.buttons["Continue"].tap()
            return
        }
        if app.buttons["Get Started"].exists && app.buttons["Get Started"].isHittable {
            app.buttons["Get Started"].tap()
            return
        }
        if app.buttons["onboardingNextButton"].exists {
            app.buttons["onboardingNextButton"].firstMatch.tap()
        }
    }

    @MainActor
    private func fillAboutYouStep(in app: XCUIApplication, name: String) {
        typeIfNeeded(app.textFields["onboardingNameField"], text: name)
        dismissKeyboardIfVisible(in: app)
        XCTAssertTrue(tapOption("26–35", in: app))
        XCTAssertTrue(tapOption("Female", in: app))
    }

    @MainActor
    private func typeIfNeeded(_ field: XCUIElement, text: String) {
        guard field.waitForExistence(timeout: 4) else { return }
        let current = field.value as? String
        if current == text { return }
        // An empty text field reports its placeholder as its value, so compare
        // against the live placeholder instead of hardcoded copies of it.
        guard current == nil || current?.isEmpty == true || current == field.placeholderValue else { return }
        // Tapping a field while the keyboard is up for another field can fail
        // to move focus; retry until this field actually owns the keyboard.
        for _ in 0..<4 {
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            field.tap()
            usleep(400_000)
        }
        if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
            field.typeText(text)
        }
    }

    @MainActor
    @discardableResult
    private func tapOption(_ label: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[label]
        if button.exists && button.isHittable {
            button.tap()
            return true
        }

        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            for _ in 0..<3 {
                scrollView.swipeUp()
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
            for _ in 0..<3 {
                scrollView.swipeDown()
                if button.exists && button.isHittable {
                    button.tap()
                    return true
                }
            }
        }
        return false
    }

    @MainActor
    private func dismissKeyboardIfVisible(in app: XCUIApplication) {
        let done = app.buttons["Done"]
        if done.exists && done.isHittable {
            done.tap()
            return
        }
        // The onboarding scroll view uses .scrollDismissesKeyboard(.interactively),
        // so a downward swipe reliably hides the keyboard when no Done button exists.
        if app.keyboards.count > 0 {
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeDown()
            }
        }
    }
}
