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

    /// Scrolls Home down until `element` can be tapped. Cards in a horizontal
    /// row are brought in by swiping that row (`row`) left.
    @discardableResult
    func reveal(_ element: XCUIElement, inRow row: String? = nil, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            if let row, scrollViews[row].exists, scrollViews[row].isHittable {
                scrollViews[row].swipeLeft()
            } else {
                swipeUp()
            }
            swipes += 1
        }
        return element.exists && element.isHittable
    }
}
