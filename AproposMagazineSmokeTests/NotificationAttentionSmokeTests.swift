import XCTest
import UIKit

/// Actual tab chrome/inbox with local effects. Red-pixel checks observe the
/// native badge rather than accepting the fixture's requested state as proof.
final class NotificationAttentionSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationAttentionSmoke"]
        if name.contains("EnglishLargestText") {
            app.launchArguments += ["-AproposNotificationAttentionEnglishSmoke",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["attention.report"].waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = originalOrientation
    }

    private func report() throws -> [String: Any] {
        let bytes = try XCTUnwrap(app.staticTexts["attention.report"].label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    private func wait(_ description: String, _ condition: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed, description)
    }
    private var favoritesTab: XCUIElement { app.tabBars.buttons.element(boundBy: 3) }
    private func capture(_ phase: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Unread navigation — " + phase; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Unread navigation AX — " + phase; tree.lifetime = .keepAlways; add(tree)
        let value = app.staticTexts["attention.report"].label
        if let bytes = value.data(using: .utf8), (try? JSONSerialization.jsonObject(with: bytes)) != nil {
            let state = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
            state.name = "Unread navigation state — " + phase; state.lifetime = .keepAlways; add(state)
        }
    }

    private func redBadgePixels() throws -> Int {
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        let image = XCUIScreen.main.screenshot().image
        let region = favoritesTab.frame.insetBy(dx: -2, dy: -2).intersection(app.tabBars.firstMatch.frame).intersection(app.frame)
        XCTAssertGreaterThan(region.width, 0); XCTAssertGreaterThan(region.height, 0)
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        let cropped = UIGraphicsImageRenderer(size: region.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -region.minX, y: -region.minY))
        }
        let cg = try XCTUnwrap(cropped.cgImage), width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))); return true
        }
        XCTAssertTrue(rendered)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] >= 180 && pixels[$0 + 1] < 125 && pixels[$0 + 2] < 140 && pixels[$0 + 3] > 200
        }.count
    }

    private func assertUnread(_ count: Int, phase: String) throws {
        wait("real current-language model count \(count)") { (try? self.report()["visibleUnreadCount"] as? Int) == count }
        let state = try report()
        XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(state["normalNotificationRuntimeUsed"] as? Bool, false)
        XCTAssertEqual(state["normalPlayerStarted"] as? Bool, false)
        XCTAssertEqual(state["OSBadgeWasSet"] as? Bool, false)
        XCTAssertEqual(state["actualShell"] as? Bool, true)
        XCTAssertEqual(state["actualInboxAndMinSidePages"] as? Bool, true)
        let pixels = try redBadgePixels()
        let native = XCTAttachment(string: "nativeRedBadgePixels=\(pixels); buttonLabel=\(favoritesTab.label); buttonValue=\(String(describing: favoritesTab.value))")
        native.name = "Unread native badge measurement — " + phase; native.lifetime = .keepAlways; add(native)
        capture(phase)
        if count == 0 { XCTAssertEqual(pixels, 0, "No red badge may remain after real read/delete or language filtering") }
        else { XCTAssertGreaterThan(pixels, 3, "The native empty-string badge must visibly render; requested state alone is not proof") }
        let unreadText = state["selectedLanguage"] as? String == "en" ? "Unread messages" : "Ulæste meddelelser"
        let spoken = favoritesTab.label + " " + (favoritesTab.value as? String ?? "")
        XCTAssertEqual(spoken.contains(unreadText), count > 0, "Existing tab must expose the unread meaning without another focus control")
    }
    private func openMessages() {
        favoritesTab.tap()
        let title = app.buttons["minside.page.messages"]
        XCTAssertTrue(title.waitForExistence(timeout: 5) && title.isHittable)
        title.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notifications.list").firstMatch.waitForExistence(timeout: 5))
    }
    private func row(_ id: String) -> XCUIElement {
        app.buttons["notifications.item.article-publication:" + id]
    }
    private func openArticle(_ id: String) throws {
        let item = row(id)
        XCTAssertTrue(item.waitForExistence(timeout: 5) && item.isHittable)
        item.tap()
        XCTAssertTrue(app.staticTexts["attention.article"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["attention.article"].label, id)
        try assertUnread(0, phase: "actual inbox tap marks article read")
        app.buttons["attention.article.back"].tap()
    }
    private func deleteArticle(_ id: String) throws {
        let item = row(id)
        XCTAssertTrue(item.waitForExistence(timeout: 5) && item.isHittable)
        let region = item.frame.intersection(app.frame), origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: region.minX + region.width * 0.85, dy: region.midY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: region.minX + region.width * 0.48, dy: region.midY)),
                withVelocity: .slow, thenHoldForDuration: 0.15)
        let delete = app.buttons["notifications.delete.article-publication:" + id]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        wait("actual row deleted") { !self.row(id).exists }
        try assertUnread(0, phase: "actual inbox swipe delete clears marker")
    }

    func testUnreadMarkerTracksRealReceiveReadDeleteAndLanguage() throws {
        try assertUnread(0, phase: "empty cold inbox")
        app.buttons["attention.receive"].tap()
        try assertUnread(1, phase: "one real received Danish article on Home")
        openMessages()
        try assertUnread(1, phase: "viewing messages alone does not mark read")
        try openArticle("0123456789abcdef01234567")
        app.buttons["attention.receive.second"].tap()
        try assertUnread(1, phase: "another genuine unread article")
        try deleteArticle("89abcdef0123456789abcdef")
        app.buttons["attention.receive.other"].tap()
        XCTAssertEqual(try report()["allUnreadCount"] as? Int, 1)
        try assertUnread(0, phase: "hidden English unread does not light Danish tab")
        app.buttons["attention.language"].tap()
        try assertUnread(1, phase: "English selection projects its actual unread")
        try openArticle("en_0123456789abcdef01234567")
        app.buttons["attention.cold"].tap()
        wait("fresh model loaded same in-memory archive") { (try? self.report()["coldReloads"] as? Int) == 1 }
        try assertUnread(0, phase: "cold model retains real read and delete truth")
        XCTAssertFalse(row("89abcdef0123456789abcdef").exists)
    }

    func testUnreadMarkerEnglishLargestText() throws {
        XCTAssertEqual(try report()["selectedLanguage"] as? String, "en")
        XCTAssertEqual(try report()["systemAccessibility"] as? Bool, true)
        try assertUnread(0, phase: "English AX5 empty inbox")
        app.buttons["attention.receive"].tap()
        try assertUnread(1, phase: "English AX5 native unread dot")
        openMessages()
        try openArticle("en_0123456789abcdef01234567")
        app.buttons["attention.receive.second"].tap()
        try assertUnread(1, phase: "English AX5 second actual message")
        try deleteArticle("en_89abcdef0123456789abcdef")
    }
}
