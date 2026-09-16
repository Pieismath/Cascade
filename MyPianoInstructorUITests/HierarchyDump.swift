import XCTest

/// Debug aid: writes the Add tab's accessibility hierarchy to SCREENSHOT_DIR.
final class HierarchyDump: XCTestCase {
    @MainActor
    func testDumpAddTab() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        let app = XCUIApplication()
        app.launch()
        app.dismissFirstLaunchChrome()
        app.tabBars.buttons["Add"].tap()
        sleep(1)
        try? app.debugDescription.write(toFile: dir + "/add-hierarchy.txt", atomically: true, encoding: .utf8)
    }
}
