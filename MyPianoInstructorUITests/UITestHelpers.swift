//
//  UITestHelpers.swift
//  MyPianoInstructorUITests
//

import XCTest

extension XCUIApplication {
    /// Gets past first-launch chrome: onboarding, the player tutorial cover, and the reminder prompt.
    func dismissFirstLaunchChrome() {
        let skip = buttons["Skip"]
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        let closeTutorial = buttons["Close tutorial"]
        if closeTutorial.waitForExistence(timeout: 6) {
            closeTutorial.tap()
            if closeTutorial.waitForExistence(timeout: 2) {
                let later = buttons["Maybe Later"]
                if later.exists { later.tap() }
                if closeTutorial.exists { closeTutorial.tap() }
            }
        }
        let notNow = alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        _ = tabBars.buttons["Home"].waitForExistence(timeout: 10)
    }
}
