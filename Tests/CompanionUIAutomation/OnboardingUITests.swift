import XCTest

/// End-to-end UI tests driving the real app in a simulator.
///
/// These complement the `CompanionUITests` package suite, which exercises
/// `AppModel` directly. Only these can prove a control is actually reachable and
/// tappable — which matters, because the add-dog form shipped with rows that
/// rendered correctly but did not respond to taps.
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Each test starts from a clean install so onboarding always runs.
        app.launchArguments += ["-companion.resetStateOnLaunch", "YES"]
        app.launch()
    }

    func testCanCompleteOnboarding() throws {
        navigateToAddDog()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Name field should exist")
        XCTAssertTrue(nameField.isHittable, "Name field must be tappable, not just visible")

        nameField.tap()
        nameField.typeText("Roxy")

        // The keyboard covers the save button, exactly as it does for a real
        // owner. "Done" is the deliberate way out; this asserts it is there.
        // Two match — the toolbar button and the return key, which is labelled
        // "Done" via `submitLabel`. Either dismisses the keyboard.
        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3), "Keyboard needs a Done button")
        doneButton.tap()

        // The form is a lazy collection view, so the save row is only realised
        // once it has been scrolled into view.
        let addButton = app.buttons["Add Roxy"]
        if !addButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add button should exist")
        XCTAssertTrue(addButton.isHittable, "Add button must be tappable")
        addButton.tap()

        XCTAssertTrue(
            app.staticTexts["Start Using Companion"].waitForExistence(timeout: 5)
                || app.buttons["Start Using Companion"].waitForExistence(timeout: 5),
            "Adding a dog should reach the ready screen"
        )
    }

    /// Every control on the add-dog form must be reachable.
    func testAddDogFormControlsAreHittable() throws {
        navigateToAddDog()

        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Name"].isHittable, "Name field is not hittable")
        XCTAssertTrue(app.textFields["Breed"].isHittable, "Breed field is not hittable")
        XCTAssertTrue(app.switches.firstMatch.isHittable, "Mixed breed toggle is not hittable")
    }

    // MARK: - Helpers

    private func navigateToAddDog() {
        app.buttons["Get Started"].firstMatch.tap()

        let continueOnDevice = app.buttons["Continue on this iPhone"].firstMatch
        XCTAssertTrue(continueOnDevice.waitForExistence(timeout: 5))
        continueOnDevice.tap()

        let firstName = app.textFields["First name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Jack")

        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["Add your dog"].waitForExistence(timeout: 5),
            "Should reach the add-dog step"
        )
    }
}
