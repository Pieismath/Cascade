//
//  ScreenshotTour.swift
//  MyPianoInstructorUITests
//
//  Walks the main screens and saves PNGs to SCREENSHOT_DIR (env var) — used
//  for design review and App Store screenshots. Skipped when the variable
//  isn't set.
//

import XCTest

final class ScreenshotTour: XCTestCase {

    @MainActor
    func testTour() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launch()

        func shot(_ name: String) {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }

        sleep(2)
        shot("00-launch")
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 20) {
            shot("01-onboarding-1")
            app.buttons["Continue"].tap()
            shot("02-onboarding-2")
            skip.tap()
        }
        let closeTutorial = app.buttons["Close tutorial"]
        if closeTutorial.waitForExistence(timeout: 6) {
            shot("03-tutorial")
            closeTutorial.tap()
            if closeTutorial.waitForExistence(timeout: 2) {
                if app.buttons["Maybe Later"].exists { app.buttons["Maybe Later"].tap() }
                if closeTutorial.exists { closeTutorial.tap() }
            }
        }
        let notNow = app.alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        _ = app.tabBars.buttons["Home"].waitForExistence(timeout: 10)

        sleep(1)
        shot("04-home-empty")
        app.swipeUp()
        sleep(1)
        shot("05-home-empty-scrolled")
        app.swipeUp()
        sleep(1)
        shot("05b-home-empty-bottom")

        // Load two starter pieces so Home has content.
        for label in ["Für Elise by Beethoven", "Twinkle Twinkle Little Star by Traditional"] {
            let card = app.buttons[label]
            if app.reveal(card, inRow: "starterPieces", maxSwipes: 12) {
                card.tap()
                if app.buttons["Export video"].waitForExistence(timeout: 10) { shot("06-player-\(label.prefix(3))") }
                let back = app.buttons["Back to library"]
                if back.waitForExistence(timeout: 5) { back.tap() }
                _ = app.tabBars.buttons["Home"].waitForExistence(timeout: 5)
                app.tabBars.buttons["Home"].tap()
            }
        }
        sleep(1)
        // Back to the top
        for _ in 0..<4 { app.swipeDown() }
        sleep(1)
        shot("07-home")
        app.swipeUp()
        sleep(1)
        shot("07b-home-scrolled")

        // Settings
        for _ in 0..<4 { app.swipeDown() }
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            sleep(2)
            shot("08-settings")
            app.swipeUp()
            sleep(1)
            shot("08b-settings-scrolled")
            app.buttons["Done"].tap()
        }

        // Sample scan
        let sample = app.buttons["Sample: Für Elise (opening)"]
        if app.reveal(sample) {
            sample.tap()
            sleep(1)
            shot("09-scan-review")
            let convert = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Convert Sample'")).firstMatch
            if convert.waitForExistence(timeout: 5) {
                convert.tap()
                usleep(700_000)
                shot("10-scan-reading")
                _ = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Save & Export Video'")).firstMatch.waitForExistence(timeout: 20)
                shot("11-scan-preview")
            }
            app.buttons["Cancel"].tap()
        }

        app.tabBars.buttons["Progress"].tap()
        sleep(1)
        shot("13-progress")
    }
}
