import XCTest

/// Debug aid: writes Home's accessibility hierarchy to SCREENSHOT_DIR.
final class HierarchyDump: XCTestCase {
    @MainActor
    func testDumpHome() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR not set")
        }
        let app = XCUIApplication()
        app.launch()
        app.dismissFirstLaunchChrome()
        sleep(1)
        try? app.debugDescription.write(toFile: dir + "/home-hierarchy.txt", atomically: true, encoding: .utf8)
    }
}
