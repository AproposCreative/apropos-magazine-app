import XCTest

final class ArticleHeaderTextSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let scenarios = ["short", "editorial"]
    private struct Rect: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Geometry: Decodable {
        let scenario: String, title: String, subtitle: String, systemCategory: String
        let before: Bool, environmentAccessibility: Bool, systemAccessibility: Bool
        let frames: [String: Rect]
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ scenario: String, before: Bool) throws -> Geometry {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposArticleHeaderTextSmoke", "-ArticleHeaderTextScenario", scenario]
        if before { app.launchArguments.append("-ArticleHeaderTextBefore") }
        app.launch()
        XCTAssertTrue(app.staticTexts["headerText.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["headerText.firebase"].label, "Firebase: ikke startet")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Klar'"), object: app.staticTexts["headerText.ready"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let value = try geometry()
        XCTAssertEqual(value.scenario, scenario)
        XCTAssertEqual(value.before, before)
        XCTAssertEqual(value.environmentAccessibility, value.systemAccessibility,
                       "The real header must inherit system text size; only fixture diagnostics are clamped")
        XCTAssertEqual(app.staticTexts["headerText.title"].label, value.title)
        XCTAssertEqual(app.staticTexts["headerText.subtitle"].label, value.subtitle)
        return value
    }
    private func geometry() throws -> Geometry {
        let raw = try XCTUnwrap(app.staticTexts["headerText.geometry"].value as? String)
        return try JSONDecoder().decode(Geometry.self, from: Data(raw.utf8))
    }
    private func frame(_ key: String, _ value: Geometry) throws -> CGRect {
        try XCTUnwrap(value.frames[key], "Missing actual layout: \(key)").frame
    }
    private func capture(_ phase: String) throws {
        let value = try geometry()
        let raw = try XCTUnwrap(app.staticTexts["headerText.geometry"].value as? String)
        let name = "\(value.before ? "Before" : "After") header — \(value.scenario) — \(value.systemCategory) — \(phase)"
        let note = XCTAttachment(string: raw); note.name = name + " geometry"
        note.lifetime = .keepAlways; add(note)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
    }
    private func reveal(_ key: String) throws {
        let scroll = app.scrollViews["headerText.scroll"]
        let viewport = scroll.frame.insetBy(dx: 0, dy: 4)
        for _ in 0..<8 {
            let target = try frame(key, geometry())
            if target.minY >= viewport.minY && target.maxY <= viewport.maxY { break }
            let upward = target.maxY > viewport.maxY
            let excess = upward ? target.maxY - viewport.maxY : viewport.minY - target.minY
            let distance = min(viewport.height / 2, max(50, excess + 12))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.midX, dy: viewport.midY + (upward ? distance / 2 : -distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.midX, dy: viewport.midY + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let target = try frame(key, geometry())
        XCTAssertGreaterThanOrEqual(target.minY, viewport.minY - 1, "\(key) must be visible for screenshot")
        XCTAssertLessThanOrEqual(target.maxY, viewport.maxY + 1, "\(key) must be visible for screenshot")
    }
    private func evidence() throws {
        try reveal("title"); try capture("top")
        // Long headers need actual scroll coverage; offscreen AX labels are not visual proof.
        try reveal("subtitle"); try capture("subtitle")
        try reveal("tags"); try capture("bottom tags")
    }

    func testBeforeMeasurementOfActualHeaderTypography() throws {
        for scenario in scenarios {
            _ = try launch(scenario, before: true)
            try evidence()
        }
    }

    func testHeaderTextRemainsBoundedAndScrollableAtActualSystemSize() throws {
        for scenario in scenarios + ["long"] {
            let value = try launch(scenario, before: false)
            let title = try frame("title", value), subtitle = try frame("subtitle", value), tags = try frame("tags", value)
            if scenario == "short" {
                // Actual single-line baseline measured before the correction at
                // both system L and AXXXL. Catch a return to fixed-size text.
                let titleHeight = try frame("text.title", value).height
                let subtitleHeight = try frame("text.subtitle", value).height
                if value.systemCategory == "UICTContentSizeCategoryAccessibilityXXXL" {
                    XCTAssertGreaterThan(titleHeight, 40.6667 * 1.5)
                    XCTAssertGreaterThan(subtitleHeight, 21.6667 * 1.5)
                } else if value.systemCategory == "UICTContentSizeCategoryL" {
                    XCTAssertEqual(titleHeight, 40.6667, accuracy: 1)
                    XCTAssertEqual(subtitleHeight, 21.6667, accuracy: 1)
                }
            }
            for key in ["title", "subtitle"] {
                let outer = try frame(key, value), text = try frame("text." + key, value)
                XCTAssertGreaterThan(text.height, 0)
                XCTAssertGreaterThanOrEqual(outer.minX, app.frame.minX - 1)
                XCTAssertLessThanOrEqual(outer.maxX, app.frame.maxX + 1)
                XCTAssertGreaterThanOrEqual(text.minX, app.frame.minX + 15)
                XCTAssertLessThanOrEqual(text.maxX, app.frame.maxX - 15)
                XCTAssertGreaterThanOrEqual(text.minY, outer.minY - 1)
                XCTAssertLessThanOrEqual(text.maxY, outer.maxY + 1)
                XCTAssertEqual(text.height, outer.height, accuracy: 1, "No fixed-height truncation in \(key)")
            }
            XCTAssertEqual(subtitle.minY - title.maxY, 16, accuracy: 1)
            XCTAssertEqual(tags.minY - subtitle.maxY, 21, accuracy: 1, "16pt stack spacing plus existing 5pt tag inset")
            XCTAssertGreaterThanOrEqual(tags.minX, app.frame.minX + 15)
            XCTAssertLessThanOrEqual(tags.maxX, app.frame.maxX - 15)
            let requiresScroll = scenario == "long" && value.systemCategory == "UICTContentSizeCategoryAccessibilityXXXL"
            if requiresScroll {
                XCTAssertGreaterThan(try frame("header", value).height, app.scrollViews["headerText.scroll"].frame.height)
            }
            try evidence()
            if requiresScroll {
                XCTAssertLessThan(try frame("header", geometry()).minY, try frame("header", value).minY - 20,
                                  "The long maximum-text header must actually scroll to reveal its final tags")
            }
            XCTAssertEqual(app.staticTexts["headerText.firebase"].label, "Firebase: ikke startet")
        }
    }
}
