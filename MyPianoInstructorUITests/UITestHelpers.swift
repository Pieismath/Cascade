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

    /// Scrolls Home until `element` is fully on screen. Cards in a horizontal
    /// row are brought in by swiping that row (`row`) left.
    ///
    /// Visibility is judged by frames: `isHittable` raises "activation point
    /// invalid" for elements parked off screen, which fails the test instead
    /// of telling us to keep scrolling.
    @discardableResult
    func reveal(_ element: XCUIElement, inRow row: String? = nil, maxSwipes: Int = 10) -> Bool {
        let screen = windows.element(boundBy: 0).frame

        func onScreen(_ candidate: XCUIElement) -> Bool {
            guard candidate.exists else { return false }
            let frame = candidate.frame
            return !frame.isEmpty && screen.contains(frame)
        }

        var swipes = 0
        while !onScreen(element) && swipes < maxSwipes {
            let strip = row.map { scrollViews[$0] }
            if let strip, strip.exists, !strip.frame.isEmpty, screen.intersects(strip.frame) {
                strip.swipeLeft()
            } else {
                swipeUp()
            }
            swipes += 1
        }
        return onScreen(element)
    }
}
