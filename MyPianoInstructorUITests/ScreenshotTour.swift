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

        shot("04-home-empty")

        let addTab = app.tabBars.buttons["Add"]
        XCTAssertTrue(addTab.waitForExistence(timeout: 10))
        addTab.tap()
        shot("05-add")

        // Load two starter songs so Home has content.
        for name in ["Für Elise", "Twinkle"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            var attempts = 0
            while !row.exists && attempts < 4 { app.swipeUp(); attempts += 1 }
            if row.waitForExistence(timeout: 5) {
                row.tap()
                if app.buttons["Export video"].waitForExistence(timeout: 10) { shot("06-player-\(name.prefix(3))") }
                let back = app.buttons["Back to library"]
                if back.waitForExistence(timeout: 5) { back.tap() }
                _ = addTab.waitForExistence(timeout: 5)
                addTab.tap()
            }
        }
        app.tabBars.buttons["Home"].tap()
        sleep(1)
        shot("07-home")

        // Song detail if reachable
        let firstSong = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Für Elise'")).firstMatch
        if firstSong.waitForExistence(timeout: 3) {
            firstSong.press(forDuration: 1.2)
            let details = app.buttons["Details"]
            if details.waitForExistence(timeout: 3) {
                details.tap()
                sleep(1)
                shot("08-song-detail")
            }
            // Relaunch rather than fight the navigation stack; onboarding is done now.
            app.terminate()
            app.launch()
            _ = app.tabBars.buttons["Add"].waitForExistence(timeout: 15)
        }

        app.tabBars.buttons["Add"].tap()
        let scanEntry = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Scan Sheet Music'")).firstMatch
        if scanEntry.waitForExistence(timeout: 5) {
            scanEntry.tap()
            sleep(1)
            shot("09-scan")
            let sample = app.buttons["Sample: Für Elise (opening)"]
            if sample.waitForExistence(timeout: 5) {
                sample.tap(); sleep(1); shot("10-scan-loaded")
                app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Convert Sample'")).firstMatch.tap()
                _ = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Save & Export Video'")).firstMatch.waitForExistence(timeout: 20)
                shot("11-scan-preview")
            }
            app.buttons["Scan settings"].tap(); sleep(1); shot("12-scan-settings")
            app.buttons["Done"].tap()
            app.buttons["Cancel"].tap()
        }

        app.tabBars.buttons["Progress"].tap()
        sleep(1)
        shot("13-progress")
    }
}
