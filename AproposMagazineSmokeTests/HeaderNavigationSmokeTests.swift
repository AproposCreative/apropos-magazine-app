import UIKit
import XCTest

/// The production MinSidePages container with actual saved rows and inbox.
/// Local callbacks do not prove account sync, article loading or notification delivery.
final class HeaderNavigationSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown
    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationInboxSmoke"]
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if name.contains("ReducedMotion") { app.launchArguments.append("-AproposMinSideReduceMotionSmoke") }
        app.launch()
        XCTAssertTrue(app.staticTexts["notifications.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["notifications.fixture.firebase"].label, "Firebase: ikke startet")
        XCTAssertTrue(app.buttons["notifications.fixture.favorite.saved-film"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = originalOrientation
    }
    private func report() throws -> [String: Any] {
        let element = app.staticTexts["notifications.fixture.report"]
        let data = try XCTUnwrap(element.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func capture(_ phase: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Header navigation — \(phase)"; shot.lifetime = .keepAlways; add(shot)
        if let value = try? report(), let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            let receipt = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
            receipt.name = "Header navigation state — \(phase)"; receipt.lifetime = .keepAlways; add(receipt)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Header navigation AX — \(phase)"; tree.lifetime = .keepAlways; add(tree)
    }
    private func isSavedPage() -> Bool {
        let saved = app.buttons["minside.page.saved"]
        if saved.exists { return saved.isSelected || saved.value as? String == "Valgt" }
        // This old-policy fallback allows the identical content-swipe assertion
        // to run before the new header exists; it is not a product fallback.
        return app.staticTexts["minside.title"].label == "Min side"
    }
    private func rowSwipeLeft(_ favorite: XCUIElement) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.width * 0.84, dy: favorite.frame.midY))
        let end = origin.withOffset(CGVector(dx: app.frame.width * 0.16, dy: favorite.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func wait(_ phase: String, _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        if result != .completed { capture("failed wait " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }
    private func frame(_ key: String) throws -> CGRect {
        let values = try XCTUnwrap(report()["frames"] as? [String: [String: Double]])
        let value = try XCTUnwrap(values[key], key)
        return CGRect(x: try XCTUnwrap(value["x"]), y: try XCTUnwrap(value["y"]),
                      width: try XCTUnwrap(value["width"]), height: try XCTUnwrap(value["height"]))
    }
    private func selected(_ page: Int) -> Bool {
        app.buttons[page == 0 ? "minside.page.saved" : "minside.page.messages"].value as? String == "Valgt"
    }
    private func endpoint(_ page: Int) {
        wait("real page endpoint \(page)") {
            guard self.selected(page), let viewport = try? self.frame("minside.viewport"),
                  let content = try? self.frame(page == 0 ? "minside.savedPage" : "minside.messagesPage"),
                  let state = try? self.report(), let paging = state["paging"] as? [String: Any] else { return false }
            return abs(content.minX - viewport.minX) < 1 && abs(content.width - viewport.width) < 1
                && abs((paging["dragTranslation"] as? Double) ?? 1) < 0.5
                && abs(((paging["progress"] as? Double) ?? -1) - Double(page)) < 0.001
        }
    }
    private func visibleTitle(_ page: Int) throws -> CGRect {
        let title = app.buttons[page == 0 ? "minside.page.saved" : "minside.page.messages"]
        let visible = title.frame.intersection(try frame("minside.header")).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 43.5, "Visible title target, including the clipped previous title")
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        return visible
    }
    private func tapTitle(_ page: Int) throws {
        let visible = try visibleTitle(page)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        endpoint(page)
    }
    private func drag(from start: CGPoint, to end: CGPoint, velocity: XCUIGestureVelocity = .fast, hold: TimeInterval = 0) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)), withVelocity: velocity, thenHoldForDuration: hold)
    }
    private func samples() throws -> [[String: Any]] { try XCTUnwrap(report()["pagingSamples"] as? [[String: Any]]) }
    private func assertIntermediate(_ sign: Double) throws {
        let intermediate = try samples().filter {
            (($0["dragTranslation"] as? Double) ?? 0) * sign > 4
                && (($0["progress"] as? Double) ?? -1) > 0 && (($0["progress"] as? Double) ?? 2) < 1
        }
        XCTAssertGreaterThanOrEqual(intermediate.count, 2, "Actual shared-container intermediate drag state; not an FPS measurement")
        XCTAssertGreaterThan(Set(intermediate.compactMap { $0["progress"] as? Double }).count, 1)
    }

    func testSavedRowSwipeRetainsMinSideAndNativeRemoval() throws {
        let favorite = app.buttons["notifications.fixture.favorite.saved-film"]
        XCTAssertTrue(favorite.isHittable)
        capture("before actual saved-row swipe")
        rowSwipeLeft(favorite)
        // The pre-change native pager changes the page here. Capture the real
        // result before asserting the new owner requirement.
        capture("actual saved-row gesture result before page and delete assertions")
        XCTAssertTrue(isSavedPage(), "List-row swipes must not navigate between Min side and Meddelelser")
        let delete = app.buttons.matching(NSPredicate(format: "label IN %@", ["Slet", "Delete"])).firstMatch
        if delete.exists && delete.isHittable {
            delete.tap()
        }
        let state = try report()
        XCTAssertTrue((state["removedFavoriteIDs"] as? [String] ?? []).contains("saved-film"),
                      "Native saved-row removal remains available; the gesture may commit or expose Slet")
        XCTAssertFalse(app.buttons["notifications.fixture.favorite.saved-film"].exists)
        XCTAssertTrue(isSavedPage())
        XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
        capture("saved-row removal keeps the same page")
    }

    func testBothLargeTitleButtonsReplaceTheBell() throws {
        capture("actual current header before two-title requirement")
        let saved = app.buttons["minside.page.saved"], messages = app.buttons["minside.page.messages"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Min side is a real title button")
        XCTAssertTrue(messages.exists, "Meddelelser is the adjacent title button")
        XCTAssertFalse(app.buttons["notifications.entry"].exists, "The bell entry is removed")
        XCTAssertEqual(saved.label, "Min side")
        XCTAssertEqual(messages.label, "Meddelelser")
        XCTAssertTrue(saved.isSelected || saved.value as? String == "Valgt")
        for control in [saved, messages, app.buttons["minside.settings"]] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
        capture("both actual large title controls with settings")
    }

    func testHeaderDragTracksBothDirectionsFromTitleAndAvailableEmptyGap() throws {
        endpoint(0)
        let header = try frame("minside.header"), title = try visibleTitle(1)
        capture("before actual header drag from a title button")
        drag(from: CGPoint(x: title.maxX - 5, y: title.midY),
             to: CGPoint(x: header.minX + 5, y: title.midY))
        endpoint(1)
        try assertIntermediate(-1)
        _ = try visibleTitle(0); _ = try visibleTitle(1)
        capture("title-origin drag commits with real intermediate page state")

        let currentHeader = try frame("minside.header")
        let titlesEnd = max(app.buttons["minside.page.saved"].frame.maxX, app.buttons["minside.page.messages"].frame.maxX)
        let hasGap = currentHeader.maxX - titlesEnd >= 90
        let x = hasGap ? titlesEnd + 5 : currentHeader.minX + 5
        drag(from: CGPoint(x: x, y: currentHeader.midY),
             to: CGPoint(x: currentHeader.maxX - 5, y: currentHeader.midY))
        endpoint(0)
        try assertIntermediate(1)
        capture(hasGap ? "actual empty header gap drag returns to saved" : "narrow header title drag returns to saved")
        XCTAssertEqual(try report()["removedFavoriteIDs"] as? [String], [])
        XCTAssertEqual(try report()["favoriteIDs"] as? [String], ["saved-film", "saved-culture", "saved-music"])
        XCTAssertEqual((try report()["path"] as? [[String: String]])?.count, 0)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }

    func testShortHeaderReleaseAndContentGesturesDoNotChangePages() throws {
        endpoint(0)
        let header = try frame("minside.header")
        let start = CGPoint(x: header.midX, y: header.midY)
        drag(from: start, to: CGPoint(x: start.x - 18, y: start.y), velocity: XCUIGestureVelocity(30), hold: 0.3)
        endpoint(0)
        let short = try samples()
        XCTAssertTrue(short.contains { (($0["dragTranslation"] as? Double) ?? 0) < -4 })
        XCTAssertFalse(short.contains { ($0["selectedPage"] as? Int) == 1 })
        capture("short slow header release settles at its starting page")
        drag(from: start, to: CGPoint(x: start.x + 2, y: start.y + 100), velocity: .slow)
        endpoint(0)
        capture("vertical header movement leaves selection unchanged")

        try tapTitle(1)
        let article = app.buttons["notifications.item.article-one"]
        XCTAssertTrue(article.isHittable)
        let origin = CGPoint(x: app.frame.width * 0.18, y: article.frame.midY)
        drag(from: origin, to: CGPoint(x: app.frame.width * 0.82, y: origin.y))
        endpoint(1)
        drag(from: CGPoint(x: app.frame.width * 0.82, y: origin.y), to: origin)
        endpoint(1)
        XCTAssertEqual((try report()["path"] as? [[String: String]])?.count, 0)
        XCTAssertEqual(try report()["opened"] as? [String], [])
        capture("horizontal gestures in actual message rows do not page or open content")
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }

    func testLargestTextTitlesSettingsAndIPadRotationRemainUsable() throws {
        endpoint(0)
        XCTAssertEqual(try report()["systemAccessibility"] as? Bool, true)
        _ = try visibleTitle(0); _ = try visibleTitle(1)
        capture("actual largest-text two-title header")
        try tapTitle(1)
        app.buttons["minside.settings"].tap()
        XCTAssertTrue(app.staticTexts["notifications.fixture.settings"].waitForExistence(timeout: 5))
        app.buttons["notifications.fixture.settings.close"].tap()
        endpoint(1)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait("actual iPad landscape") { self.app.frame.width > self.app.frame.height }
            endpoint(1)
            _ = try visibleTitle(0); _ = try visibleTitle(1)
            capture("largest text after actual iPad landscape rotation")
            XCUIDevice.shared.orientation = .portrait
            wait("actual iPad portrait") { self.app.frame.height > self.app.frame.width }
            endpoint(1)
        }
        try tapTitle(0)
        _ = try visibleTitle(0); _ = try visibleTitle(1)
        XCTAssertEqual(try report()["settingsRequests"] as? Int, 1)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
        capture("largest text returns to saved with the same settings callback")
    }

    func testReducedMotionHeaderTapAndDragUseTheSamePages() throws {
        endpoint(0)
        XCTAssertEqual(try report()["reduceMotionOverride"] as? Bool, true)
        XCTAssertEqual((try report()["paging"] as? [String: Any])?["reduceMotion"] as? Bool, true)
        capture("reported fixture reduce-motion override with real system setting")
        try tapTitle(1); try tapTitle(0)
        let header = try frame("minside.header")
        drag(from: CGPoint(x: header.maxX - 5, y: header.midY),
             to: CGPoint(x: header.minX + 5, y: header.midY))
        endpoint(1)
        try tapTitle(0)
        XCTAssertTrue(try samples().allSatisfy { $0["reduceMotion"] as? Bool == true })
        XCTAssertEqual(try report()["removedFavoriteIDs"] as? [String], [])
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
        capture("reduced-motion presentation retains tap and header-only drag navigation")
    }

    func testSlowHeaderDragPixelsBothDirections() throws {
        endpoint(0)
        capture("focused slow two-way motion starts on saved")
        for destination in [1, 0] {
            let header = try frame("minside.header")
            let start = CGPoint(x: destination == 1 ? header.maxX - 5 : header.minX + 5, y: header.midY)
            let end = CGPoint(x: destination == 1 ? header.minX + 5 : header.maxX - 5, y: header.midY)
            drag(from: start, to: end, velocity: XCUIGestureVelocity(100), hold: 0.15)
            endpoint(destination)
            try assertIntermediate(destination == 1 ? -1 : 1)
            capture(destination == 1 ? "slow drag reaches messages" : "slow drag returns to saved")
        }
        XCTAssertEqual(try report()["opened"] as? [String], [])
        XCTAssertEqual(try report()["removedFavoriteIDs"] as? [String], [])
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }
}
