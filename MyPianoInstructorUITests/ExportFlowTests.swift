//
//  ExportFlowTests.swift
//  MyPianoInstructorUITests
//
//  End-to-end: first launch → onboarding → starter piece on Home → player →
//  video export → share sheet. Exercises the offline audio render, the
//  CoreGraphics frame writer, and the merge on a real (simulated) device.
//

import XCTest

final class ExportFlowTests: XCTestCase {

    @MainActor
    func testStarterSongExportsAVideo() throws {
        let app = XCUIApplication()
        app.launch()

        // Onboarding (first launch only)
        app.dismissFirstLaunchChrome()

        // Home → Starter pieces → Twinkle
        let twinkle = app.buttons["Twinkle Twinkle Little Star by Traditional"]
        XCTAssertTrue(app.reveal(twinkle, inRow: "starterPieces", maxSwipes: 12), "starter piece not reachable")
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
