import XCTest

final class ArticleLoadingSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposArticleLoadingSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["loading.fixture.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["loading.fixture.firebase"].label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func waitStatus(_ text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text),
            object: app.staticTexts["loading.fixture.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed)
    }
    private func ready(_ article: String = "A", revision: Int = 1) {
        waitStatus("Historie \(article) · udgave \(revision) · ready")
        XCTAssertTrue(app.webViews.staticTexts["Historie \(article) · udgave \(revision)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reader.bodyRetry"].exists)
        XCTAssertFalse(app.staticTexts["Klargør artiklen…"].exists)
    }
    private func failed(_ title: String) {
        let retry = app.buttons["reader.bodyRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        if !retry.isHittable { app.scrollViews["loading.fixture.scroll"].swipeUp() }
        XCTAssertTrue(retry.isHittable)
        XCTAssertEqual(retry.label, "Prøv igen")
        XCTAssertTrue(app.staticTexts["Artiklen kunne ikke vises."].exists)
        XCTAssertFalse(app.staticTexts["Artiklen skal hentes på ny."].exists)
        capture(title)
        retry.tap()
        ready()
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDelayedTextAndLocalRetryAfterProcessAndNavigationFailures() {
        waitStatus("Historie A · udgave 1 · preparing")
        XCTAssertTrue(app.staticTexts["Klargør artiklen…"].exists)
        XCTAssertFalse(app.buttons["reader.bodyRetry"].exists)
        capture("Artikel — tydelig lokal klargøring")
        app.buttons["loading.fixture.release"].tap()
        ready()
        capture("Artikel — faktisk tekst efter klargøring")
        app.buttons["loading.fixture.terminate"].tap()
        failed("Artikel — processtop giver læsbar lokal retry")
        app.buttons["loading.fixture.fail"].tap()
        failed("Artikel — navigationsfejl giver lokal retry")
        app.buttons["loading.fixture.provisional"].tap()
        failed("Artikel — tidlig navigationsfejl giver lokal retry")
    }
    func testDelayedOldArticleCannotReplaceBOrNewA() {
        waitStatus("Historie A · udgave 1 · preparing")
        app.buttons["loading.fixture.b"].tap()
        waitStatus("Historie B · udgave 2 · preparing")
        app.buttons["loading.fixture.a"].tap()
        waitStatus("Historie A · udgave 3 · preparing")
        app.buttons["loading.fixture.release"].tap()
        ready("A", revision: 3)
        XCTAssertFalse(app.webViews.staticTexts["Historie A · udgave 1"].exists)
        XCTAssertFalse(app.webViews.staticTexts["Historie B · udgave 2"].exists)
        capture("Artikel — gammelt arbejde kan ikke erstatte nyt A")
        app.buttons["loading.fixture.b"].tap()
        ready("B", revision: 4)
        XCTAssertFalse(app.webViews.staticTexts["Historie A · udgave 3"].exists)
    }
}
