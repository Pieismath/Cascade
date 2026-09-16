//
//  SampleScanFlowTests.swift
//  MyPianoInstructorUITests
//
//  End-to-end: Add tab → Scan Sheet Music → bundled sample → Convert →
//  preview → Save & Export Video → share sheet. Covers the whole
//  "sheet music in, video out" path without network or credits.
//

import XCTest

final class SampleScanFlowTests: XCTestCase {

    @MainActor
    func testSampleScanProducesAVideo() throws {
        let app = XCUIApplication()
        app.launch()

        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        let closeTutorial = app.buttons["Close tutorial"]
        if closeTutorial.waitForExistence(timeout: 5) { closeTutorial.tap() }
        let notNow = app.alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }

        let addTab = app.tabBars.buttons["Add"]
        XCTAssertTrue(addTab.waitForExistence(timeout: 10))
        addTab.tap()

        let scanEntry = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Scan Sheet Music'")).firstMatch
        XCTAssertTrue(scanEntry.waitForExistence(timeout: 10), "scan entry card not found")
        scanEntry.tap()

        let sample = app.buttons["Sample: Für Elise (opening)"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "sample picker not shown")
        sample.tap()

        let convert = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Convert Sample'")).firstMatch
        XCTAssertTrue(convert.waitForExistence(timeout: 5), "convert button not found")
        convert.tap()

        let export = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Save & Export Video'")).firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 20), "preview did not appear")
        export.tap()

        XCTAssertTrue(app.staticTexts["Exporting Video"].waitForExistence(timeout: 10))

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
