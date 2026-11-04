import XCTest

final class ArticleMediaSmokeTests: XCTestCase {
    func testLateImageFailureKeepsCreditAndProseInPlaceThenNewArticleIsClean() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposArticleMediaSmoke"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["media.fixture.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["media.fixture.firebase"].label, "Firebase: ikke startet")
        let status = app.staticTexts["media.fixture.status"]
        func wait(_ text: String) {
            let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: status)
            XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 12), .completed)
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        wait("A · ready")
        let scroll = app.scrollViews["media.fixture.scroll"]
        let credit = app.webViews.staticTexts["Foto: Apropos · lokal prøve"]
        for _ in 0..<6 { if credit.isHittable { break }; scroll.swipeUp() }
        XCTAssertTrue(credit.isHittable)
        capture("Inlinebillede — original plads og kredit")
        app.buttons["media.fixture.fail"].tap()
        wait("Billedfejl vist")
        let data = try XCTUnwrap((status.value as? String)?.data(using: .utf8))
        let measurements = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        let before = try XCTUnwrap(measurements["before"]), after = try XCTUnwrap(measurements["after"])
        for field in ["slot", "credit", "after", "height"] {
            let first = try XCTUnwrap(before[field] as? Double), last = try XCTUnwrap(after[field] as? Double)
            XCTAssertEqual(first, last, accuracy: 1, "Billedfejl må ikke ændre \(field)")
        }
        XCTAssertTrue(app.webViews.staticTexts["Billedet kunne ikke indlæses"].exists)
        XCTAssertFalse(app.webViews.staticTexts["Tjek din internetforbindelse"].exists)
        XCTAssertTrue(credit.exists)
        capture("Inlinebillede — neutral fejl og bevaret plads")
        app.buttons["media.fixture.b"].tap(); wait("B · ready")
        XCTAssertTrue(app.webViews.staticTexts["Historie B. Et øjeblik til at se nærmere."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.webViews.staticTexts["Billedet kunne ikke indlæses"].exists)
        XCTAssertTrue(app.webViews.images["Lokalt prøvebillede"].exists)
        capture("Inlinebillede — ny artikel uden gammel fejl")
    }
}
