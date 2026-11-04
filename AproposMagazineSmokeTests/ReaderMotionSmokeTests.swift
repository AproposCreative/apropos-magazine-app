import XCTest

final class ReaderMotionSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderMotionSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["motion.ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tekstombrydning: ok"].waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }
    private var line: XCUIElement { app.descendants(matching: .any).matching(identifier: "reader.progress").firstMatch }
    private var percent: Int { Int((line.value as? String ?? "").components(separatedBy: " ").first ?? "") ?? -1 }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testMeasuredProgressFollowsProseAndStopsBeforeRelatedContent() {
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(percent, 0)
        let scroll = app.scrollViews["motion.scroll"]
        for _ in 0..<6 {
            scroll.swipeUp()
            if percent > 0 { break }
        }
        XCTAssertGreaterThan(percent, 0)
        XCTAssertLessThan(percent, 100)
        capture("Læselinje — midt i artikel")
        for _ in 0..<40 {
            if percent == 100 { break }
            scroll.swipeUp()
        }
        XCTAssertEqual(percent, 100)
        scroll.swipeUp()
        XCTAssertEqual(percent, 100)
        capture("Læselinje — færdig før relateret indhold")
        for _ in 0..<3 { scroll.swipeDown() }
        XCTAssertLessThan(percent, 100)
        XCTAssertGreaterThan(percent, 0)
        capture("Læselinje — tilbage i artikel")
    }
    func testReducedMotionKeepsProseAndProgressAvailable() {
        app.switches["motion.reduced"].switches.firstMatch.tap()
        let scroll = app.scrollViews["motion.scroll"]
        for _ in 0..<6 {
            scroll.swipeUp()
            if percent > 0 { break }
        }
        XCTAssertGreaterThan(percent, 0)
        XCTAssertLessThan(percent, 100)
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].exists)
        capture("Reducer bevægelse — læsbar artikel og linje")
    }
}
