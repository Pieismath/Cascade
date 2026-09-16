//
//  LaunchTests.swift
//  MyPianoInstructorUITests
//
//  Smoke test: the app launches and reaches either onboarding or the tab bar
//  without crashing.
//

import XCTest

final class LaunchTests: XCTestCase {

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        let onboarding = app.buttons["Next"]
        let home = app.tabBars.buttons["Home"]
        let reached = onboarding.waitForExistence(timeout: 10) || home.waitForExistence(timeout: 10)
        XCTAssertTrue(reached, "App did not reach onboarding or the home tab")
    }
}
