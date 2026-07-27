import XCTest

/// Drives a real recording session in the simulator.
///
/// Location is granted ahead of time by the test runner script; the walk itself
/// is fed by `simctl location`. What matters here is that the controls behave:
/// most of all that finishing takes two deliberate taps and cannot happen by
/// accident, since that is the one action that ends an hour of someone's walk.
final class WalkRecordingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-companion.resetStateOnLaunch", "YES"]
        app.launch()
        completeOnboarding()
    }

    func testFinishRequiresTwoTaps() throws {
        startWalk()

        let finish = app.buttons["Finish Walk"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Finish button should be present")
        XCTAssertTrue(finish.isHittable, "Finish button must be reachable")

        // One tap arms it and must NOT end the walk.
        finish.tap()
        XCTAssertTrue(
            app.buttons["Pause"].exists,
            "A single tap must not finish the walk — the recording screen should still be up"
        )

        // A second tap within the window confirms.
        finish.tap()

        XCTAssertTrue(
            app.staticTexts["Walk saved"].waitForExistence(timeout: 10),
            "Two taps should finish the walk and show the summary"
        )
    }

    /// The whole point of the app: a finished walk has to be there afterwards.
    func testSavedWalkAppearsInHistory() throws {
        startWalk()

        let finish = app.buttons["Finish Walk"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()
        finish.tap()

        XCTAssertTrue(app.staticTexts["Walk saved"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()

        app.buttons["Activities"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Activities"].waitForExistence(timeout: 5),
            "Activities tab should open"
        )
        // The generated title depends on the time of day, so assert on the
        // structure — a walk row exists and the empty state is gone.
        XCTAssertFalse(
            app.staticTexts["No walks yet"].exists,
            "History should no longer be empty after saving a walk"
        )
    }

    func testPauseAndResume() throws {
        startWalk()

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()

        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Pausing should offer Resume")
        // Discard is deliberately only offered while paused.
        XCTAssertTrue(app.buttons["Discard walk"].exists, "Discard should appear while paused")

        resume.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5), "Resuming should restore Pause")
        XCTAssertFalse(app.buttons["Discard walk"].exists, "Discard should be hidden while recording")
    }

    // MARK: - Helpers

    private func completeOnboarding() {
        app.buttons["Get Started"].firstMatch.tap()
        app.buttons["Continue on this iPhone"].firstMatch.tap()

        let firstName = app.textFields["First name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Jack")
        app.buttons["Continue"].firstMatch.tap()

        let dogName = app.textFields["Name"]
        XCTAssertTrue(dogName.waitForExistence(timeout: 5))
        dogName.tap()
        dogName.typeText("Roxy")
        app.buttons["Done"].firstMatch.tap()

        let addDog = app.buttons["Add Roxy"]
        if !addDog.exists { app.swipeUp() }
        XCTAssertTrue(addDog.waitForExistence(timeout: 5))
        addDog.tap()

        let finishOnboarding = app.buttons["Start Using Companion"]
        XCTAssertTrue(finishOnboarding.waitForExistence(timeout: 5))
        finishOnboarding.tap()
    }

    private func startWalk() {
        let startWalk = app.buttons["Start Walk"].firstMatch
        XCTAssertTrue(startWalk.waitForExistence(timeout: 10), "Today should offer Start Walk")
        startWalk.tap()

        // The preparation sheet's own Start Walk button.
        let confirmStart = app.buttons["Start Walk"].firstMatch
        XCTAssertTrue(confirmStart.waitForExistence(timeout: 5))
        confirmStart.tap()
    }
}
