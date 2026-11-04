import XCTest
import UIKit

final class ArticleBackSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposArticleBackSmoke"]
        if name.contains("Zoom") { app.launchArguments.append("-AproposArticleBackZoom") }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["article.back.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["article.back.fixture.firebase"].label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func report() throws -> [String: Any] {
        let raw = try XCTUnwrap(app.staticTexts["article.back.fixture.state"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }
    private func waitDepth(_ depth: Int) throws {
        let target = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? self.report()["depth"] as? Int) == depth
        }, object: nil)
        let result = XCTWaiter.wait(for: [target], timeout: 6)
        if result != .completed { try capture("depth \(depth) not reached") }
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }
    private func waitReady(_ index: Int) {
        let ready = app.staticTexts["article.back.fixture.ready"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == YES AND label == %@", "Artikel klar \(index)"), object: ready)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed)
    }
    private func open() throws {
        let open = app.buttons["article.back.fixture.open"]
        XCTAssertTrue(open.exists && open.isHittable); open.tap()
        try waitDepth(1); waitReady(1)
    }
    private func edge(_ y: CGFloat, fraction: CGFloat = 0.80,
                      velocity: XCUIGestureVelocity = .slow, hold: TimeInterval = 0.08) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.minX + 2, dy: y))
        let end = origin.withOffset(CGVector(dx: app.frame.minX + app.frame.width * fraction, dy: y))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: hold)
    }
    private func capture(_ title: String) throws {
        let png = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        png.name = "Article back — \(title)"; png.lifetime = .keepAlways; add(png)
        var state = try report()
        let native = app.descendants(matching: .any).matching(identifier: "article.back.fixture.native").firstMatch
        if native.exists { state["native"] = native.value as? String }
        let bytes = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let json = XCTAttachment(string: String(decoding: bytes, as: UTF8.self))
        json.name = "Article back state — \(title)"; json.lifetime = .keepAlways; add(json)
    }
    func testPlainArticleNativeEdgeBackAcrossHeaderBodyAndReopen() throws {
        try exerciseHeaderAndBody()
    }
    func testZoomArticleNativeEdgeBackAcrossHeaderBodyAndReopen() throws {
        try exerciseHeaderAndBody()
    }
    private func exerciseHeaderAndBody() throws {
        try open()
        let header = app.staticTexts["article.back.fixture.header"]
        XCTAssertTrue(header.exists)
        try capture("header before edge")
        edge(header.frame.midY)
        try waitDepth(0)
        try capture("header returned root")
        try open()
        let scroll = app.scrollViews["article.back.fixture.scroll"]
        scroll.swipeUp(velocity: .slow)
        let body = app.webViews.firstMatch
        XCTAssertTrue(body.exists)
        let visible = body.frame.intersection(scroll.frame).intersection(app.frame)
        XCTAssertGreaterThan(visible.height, 100)
        try capture("scrolled shared HTML before edge")
        edge(visible.midY)
        try waitDepth(0)
        try capture("HTML returned root")
    }
    func testShortEdgeKeepsValidNavigationThenCarouselAndSecondPush() throws {
        try open()
        let header = app.staticTexts["article.back.fixture.header"]
        // A two-point one-way edge can legally finish even at low velocity.
        // Without a reverse path this is not an interactive-cancellation test.
        edge(header.frame.midY, fraction: 0.06, velocity: XCUIGestureVelocity(rawValue: 30), hold: 0.3)
        let shortEdgeDepth = try XCTUnwrap(try report()["depth"] as? Int)
        XCTAssertTrue([0, 1].contains(shortEdgeDepth))
        try capture("short edge legal native outcome depth \(shortEdgeDepth)")
        if shortEdgeDepth == 0 { try open() }
        try waitDepth(1)
        try capture("article1 available after short edge")
        let carousel = app.scrollViews["article.back.fixture.carousel"]
        XCTAssertTrue(carousel.exists && carousel.isHittable)
        carousel.swipeLeft(velocity: .slow)
        try waitDepth(1)
        carousel.swipeRight(velocity: .slow)
        try waitDepth(1)
        try capture("horizontal carousel did not dismiss")
        let next = app.buttons["article.back.fixture.next"]
        XCTAssertTrue(next.isHittable); next.tap()
        try waitDepth(2); waitReady(2)
        try capture("second article before edge")
        edge(app.staticTexts["article.back.fixture.header"].frame.midY)
        try waitDepth(1)
        try capture("edge popped exactly one")
        XCTAssertEqual(try report()["path"] as? [Int], [1])
        edge(app.staticTexts["article.back.fixture.header"].frame.midY)
        try waitDepth(0)
    }
}
