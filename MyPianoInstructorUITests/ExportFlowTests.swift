//
//  ExportFlowTests.swift
//  MyPianoInstructorUITests
//
//  End-to-end: first launch → onboarding → starter song → player → video
//  export → share sheet. Exercises the offline audio render, the CoreGraphics
//  frame writer, and the merge on a real (simulated) device.
//

import XCTest

final class ExportFlowTests: XCTestCase {

    @MainActor
    func testStarterSongExportsAVideo() throws {
        let app = XCUIApplication()
        app.launch()

        // Onboarding (first launch only)
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }

        // Player tutorial is queued after the first onboarding dismissal.
        let closeTutorial = app.buttons["Close tutorial"]
        if closeTutorial.waitForExistence(timeout: 5) { closeTutorial.tap() }

        // Notification prompt (shows on launches where the tutorial didn't)
        let notNow = app.alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }

        // Add tab → starter library → Twinkle
        let addTab = app.tabBars.buttons["Add"]
        XCTAssertTrue(addTab.waitForExistence(timeout: 10), "tab bar not found")
        addTab.tap()

        let twinkle = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Twinkle'")).firstMatch
        XCTAssertTrue(twinkle.waitForExistence(timeout: 10), "starter song not listed")
        twinkle.tap()

        // Player opens (landscape). Export button has an accessibility label.
        let export = app.buttons["Export video"]
        XCTAssertTrue(export.waitForExistence(timeout: 15), "player export button not found")
        export.tap()

        // Progress sheet appears, then the system share sheet once rendering is done.
        XCTAssertTrue(app.staticTexts["Exporting Video"].waitForExistence(timeout: 10), "export progress sheet did not appear")

        let shareSheet = app.otherElements["ActivityListView"]
        let failedAlert = app.alerts["Export Failed"]
        let deadline = Date().addingTimeInterval(240)
        var finished = false
        while Date() < deadline {
            if shareSheet.exists { finished = true; break }
            if failedAlert.exists { XCTFail("export reported failure"); return }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(finished, "share sheet did not appear within 4 minutes")
    }
}
