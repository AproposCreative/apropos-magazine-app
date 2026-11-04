import XCTest
import UIKit

/// Actual MinSidePages and NotificationInboxView with their existing injected
/// device-local model. No APNs delivery, live account, article or audio service.
final class NotificationDismissalSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown
    private let typedIDs = ["article-one", "audio-two", "narration-four"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationInboxSmoke"]
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["notifications.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["notifications.fixture.firebase"].label, "Firebase: ikke startet")
        XCTAssertTrue(app.buttons["minside.page.messages"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = originalOrientation
    }

    private func state() throws -> [String: Any] {
        let element = app.staticTexts["notifications.fixture.report"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(element.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func capture(_ phase: String) {
        // Preserve the original full-screen image, including landscape EXIF.
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "Notification dismissal screen — " + phase
        screen.lifetime = .keepAlways; add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Notification dismissal AX — " + phase
        tree.lifetime = .keepAlways; add(tree)
        if let report = try? state(),
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = "Notification dismissal state — " + phase
            receipt.lifetime = .keepAlways; add(receipt)
        }
    }

    private func wait(_ phase: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        if result != .completed { capture("failed wait: " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }

    private var list: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "notifications.list").firstMatch
    }

    private func row(_ id: String) -> XCUIElement {
        let prefix = id == "manual-three" ? "notifications.message." : "notifications.item."
        return app.descendants(matching: .any).matching(identifier: prefix + id).firstMatch
    }

    private func reportedFrame(_ key: String) throws -> CGRect {
        let frames = try XCTUnwrap(state()["frames"] as? [String: [String: Double]])
        let value = try XCTUnwrap(frames[key], key)
        return CGRect(x: try XCTUnwrap(value["x"]), y: try XCTUnwrap(value["y"]),
                      width: try XCTUnwrap(value["width"]), height: try XCTUnwrap(value["height"]))
    }

    private func viewport() throws -> CGRect {
        let header = try reportedFrame("minside.header")
        let visibleList = list.frame.intersection(app.frame)
        let result = visibleList.intersection(CGRect(x: app.frame.minX,
            y: max(visibleList.minY, header.maxY + 2), width: app.frame.width,
            height: max(0, app.frame.maxY - max(visibleList.minY, header.maxY + 2) - 8)))
        XCTAssertFalse(result.isNull)
        XCTAssertGreaterThan(result.height, 80)
        return result
    }

    private func visibleRow(_ id: String) throws -> CGRect {
        let element = row(id)
        for _ in 0..<12 {
            if element.exists {
                let visible = element.frame.intersection(try viewport())
                if !visible.isNull && visible.width > 120 && visible.height > 64 { return visible }
            }
            if id == "manual-three" { list.swipeUp(velocity: .slow) }
            else { list.swipeDown(velocity: .slow) }
        }
        capture("row not visibly reachable: " + id)
        XCTFail("Notification row must intersect the actual list viewport: " + id)
        return .zero
    }

    private func drag(from start: CGPoint, to end: CGPoint, velocity: XCUIGestureVelocity = .slow) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)),
            withVelocity: velocity, thenHoldForDuration: 0.15)
    }

    private func partialSwipe(_ id: String) throws {
        let visible = try visibleRow(id)
        // Stay well short of the full-swipe threshold. The coordinates come
        // from the real visible row, never from a forced fixture frame.
        drag(from: CGPoint(x: visible.minX + visible.width * 0.85, y: visible.midY),
             to: CGPoint(x: visible.minX + visible.width * 0.48, y: visible.midY))
    }

    private func fullSwipe(_ id: String) throws {
        let visible = try visibleRow(id)
        drag(from: CGPoint(x: visible.maxX - 8, y: visible.midY),
             to: CGPoint(x: visible.minX + 3, y: visible.midY))
    }

    private func assertMessages() throws {
        wait("messages page remains selected") {
            self.app.buttons["minside.page.messages"].value as? String == "Valgt"
        }
        let paging = try XCTUnwrap(state()["paging"] as? [String: Any])
        XCTAssertEqual(paging["selectedPage"] as? Int, 1)
        XCTAssertEqual(paging["progress"] as? Double, 1)
        XCTAssertTrue(app.buttons["minside.settings"].isHittable)
    }

    private func assertNoOpen(_ expectedCount: Int) throws {
        wait("local unread model and badge spy equal remaining messages") {
            guard let report = try? self.state(), let removed = report["removed"] as? [String] else { return false }
            // The generic, unclassified message is visible-only. Only the three
            // recognized typed deliveries are admitted to the durable badge.
            let expectedBadge = Set(self.typedIDs).subtracting(Set(removed)).count
            return report["localUnreadCount"] as? Int == expectedCount
                && report["qualifiedUnreadCount"] as? Int == expectedBadge
                && report["recordedBadgeValue"] as? Int == expectedBadge
        }
        let report = try state()
        XCTAssertEqual(report["count"] as? Int, expectedCount)
        XCTAssertEqual(report["badgeEffectIsLocalSpyNotOSBadge"] as? Bool, true)
        XCTAssertEqual(report["attempts"] as? [String], [])
        XCTAssertEqual(report["opened"] as? [String], [])
        XCTAssertEqual(report["openTypes"] as? [String], [])
        XCTAssertEqual((report["path"] as? [[String: String]])?.count, 0)
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(report["fixtureIssue"] as? String, "")
        XCTAssertFalse(app.staticTexts["notifications.fixture.destination"].exists)
        try assertMessages()
    }

    private func openMessages() throws {
        let title = app.buttons["minside.page.messages"]
        let visible = title.frame.intersection(try reportedFrame("minside.header")).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        XCTAssertGreaterThanOrEqual(visible.width, 43.5)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        try assertMessages()
        wait("four actual local messages loaded") { (try? self.state()["count"] as? Int) == 4 }
        try assertNoOpen(4)
    }

    private func deleteButton(_ id: String) -> XCUIElement {
        let identified = app.buttons["notifications.delete." + id]
        if identified.exists { return identified }
        // UIKit may expose a contextual action by its semantic title while
        // omitting SwiftUI's identifier. Only the currently revealed action
        // is admitted, and tapDelete also intersects its real list viewport.
        return app.buttons.matching(NSPredicate(format: "label IN %@", ["Slet", "Delete"]))
            .allElementsBoundByIndex.first(where: { $0.isHittable && $0.frame.intersects(self.list.frame) })
            ?? app.buttons.matching(NSPredicate(format: "label IN %@", ["Slet", "Delete"])).firstMatch
    }

    private func tapDelete(_ id: String, expectedCount: Int) throws {
        let action = deleteButton(id)
        wait("actual native destructive action for " + id) { action.exists && action.isHittable }
        XCTAssertTrue(["Slet", "Delete"].contains(action.label), action.label)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        let visible = action.frame.intersection(try viewport())
        XCTAssertGreaterThan(visible.width, 0)
        XCTAssertGreaterThan(visible.height, 0)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
        wait("deleted message disappears: " + id) {
            !self.row(id).exists && (try? self.state()["count"] as? Int) == expectedCount
        }
        let removed = try XCTUnwrap(state()["removed"] as? [String])
        XCTAssertTrue(removed.contains(id))
        try assertNoOpen(expectedCount)
    }

    private func pullRefreshWithoutResurrection(expectedCount: Int, removedIDs: Set<String>) throws {
        let before = try XCTUnwrap(state()["deliveredReads"] as? Int)
        let visible = try viewport()
        // Use the tall iPad viewport for a longer native pull. The receipt
        // below still requires the existing refresh callback to run.
        let pullEndOffset = app.frame.width > 600
            ? min(visible.height - 20, visible.height * 0.65)
            : min(visible.height - 20, 260)
        drag(from: CGPoint(x: visible.midX, y: visible.minY + 18),
             to: CGPoint(x: visible.midX, y: visible.minY + pullEndOffset))
        wait("real refresh invokes injected delivered effect") {
            ((try? self.state()["deliveredReads"] as? Int) ?? -1) > before
        }
        try assertNoOpen(expectedCount)
        for id in removedIDs { XCTAssertFalse(row(id).exists, id) }
        let removed = try XCTUnwrap(state()["removed"] as? [String])
        XCTAssertEqual(Set(removed), removedIDs)
    }

    func testArticlePartialSwipeCancelAndDeleteRetainsMessagesAndRefresh() throws {
        try openMessages()
        capture("initial four notifications")
        try partialSwipe("article-one")
        capture("actual partial article swipe before destructive-action requirement")
        let action = deleteButton("article-one")
        wait("partial article swipe reveals Slet") { action.exists && action.isHittable }
        try assertNoOpen(4)
        XCTAssertEqual(try state()["removed"] as? [String], [])
        capture("red native article delete exposed without activation")

        let visible = try visibleRow("article-one")
        drag(from: CGPoint(x: visible.minX + visible.width * 0.18, y: visible.midY),
             to: CGPoint(x: visible.minX + visible.width * 0.74, y: visible.midY))
        wait("reverse row pan closes action without deletion") { !action.exists || !action.isHittable }
        try assertNoOpen(4)
        XCTAssertEqual(try state()["removed"] as? [String], [])
        capture("partial swipe cancelled without open or removal")

        // The same method can be run on the existing iPad destination. This is
        // actual system orientation, not a simulated size-class/frame override.
        if app.frame.width > 600 {
            XCUIDevice.shared.orientation = .landscapeLeft
            wait("iPad actual landscape screen") { self.app.frame.width > self.app.frame.height }
            try assertNoOpen(4)
            capture("iPad landscape after cancelling notification action")
            XCUIDevice.shared.orientation = .portrait
            wait("iPad returns to portrait") { self.app.frame.height > self.app.frame.width }
            try assertNoOpen(4)
        }
        try partialSwipe("article-one")
        capture("article action revealed again before explicit delete")
        try tapDelete("article-one", expectedCount: 3)
        XCTAssertTrue(row("audio-two").exists)
        XCTAssertTrue(row("narration-four").exists)
        XCTAssertTrue(row("manual-three").exists)
        XCTAssertEqual(try state()["removed"] as? [String], ["article-one"])
        capture("only article removed and messages stays selected")
        try pullRefreshWithoutResurrection(expectedCount: 3, removedIDs: ["article-one"])
        capture("real pull refresh does not resurrect article")
    }

    func testGenericFullSwipeDeletesAndRemainingRowsReachEmptyLargestText() throws {
        try openMessages()
        XCTAssertEqual(try state()["systemAccessibility"] as? Bool, true)
        XCTAssertEqual(try state()["systemTextCategory"] as? String, "UICTContentSizeCategoryAccessibilityXXXL")
        _ = try visibleRow("manual-three")
        capture("actual visible generic message at largest text before full swipe")
        try fullSwipe("manual-three")
        capture("actual generic full-swipe result before delete assertion")
        wait("full swipe deletes generic without opening") {
            !self.row("manual-three").exists && (try? self.state()["count"] as? Int) == 3
        }
        try assertNoOpen(3)
        XCTAssertEqual(try state()["removed"] as? [String], ["manual-three"])
        capture("generic full swipe removed text-only row without a route")

        for (index, id) in typedIDs.enumerated() {
            try partialSwipe(id)
            capture("largest text native action for " + id)
            try tapDelete(id, expectedCount: 2 - index)
        }
        let empty = app.descendants(matching: .any).matching(identifier: "notifications.empty").firstMatch
        wait("actual inbox empty state") { empty.exists }
        XCTAssertTrue(app.staticTexts["Ingen meddelelser"].exists)
        try assertNoOpen(0)
        XCTAssertEqual(Set(try XCTUnwrap(state()["removed"] as? [String])),
                       Set(typedIDs + ["manual-three"]))
        capture("all four removed and real empty messages state")
        try pullRefreshWithoutResurrection(expectedCount: 0, removedIDs: Set(typedIDs + ["manual-three"]))
        XCTAssertTrue(empty.exists)
        capture("empty messages remains empty after real delivered refresh")
    }
}
