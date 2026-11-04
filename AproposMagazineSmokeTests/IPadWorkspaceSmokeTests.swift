import UIKit
import XCTest

/// Same navigation shell and actual Search/Categories as production. Local
/// Home/account roots and memory playback do not prove those live screens.
final class IPadWorkspaceSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad navigation destination")
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposHomeSmoke", "-HomeSmokeScenario", "listNavigation"]
        app.launch()
        XCTAssertTrue(app.staticTexts["list.navigation.state"].waitForExistence(timeout: 10))
        wait { self.app.frame.width > self.app.frame.height }
        XCTAssertTrue(app.buttons["ipad.navigation.search"].waitForExistence(timeout: 5))
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        XCUIDevice.shared.orientation = originalOrientation
    }

    private func report() -> [String: Any] {
        guard let value = app.staticTexts["list.navigation.state"].value as? String,
              let data = value.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Missing actual navigation receipt"); return [:]
        }
        return result
    }

    private func wait(_ condition: @escaping () -> Bool) {
        let check = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 8), .completed)
    }

    private func select(_ id: String) {
        let item = app.buttons["ipad.navigation." + id]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isHittable)
        XCTAssertGreaterThanOrEqual(item.frame.width, 44)
        XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        item.tap()
    }

    private func prepareSearch() {
        select("search")
        let toggle = app.buttons["search.controls.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        let query = app.textFields["search.controls.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Rejse\n")
        wait { !self.app.keyboards.firstMatch.exists }
        app.buttons["search.controls.sort"].tap()
        let titleSort = app.buttons["Titel A-Å"].firstMatch
        XCTAssertTrue(titleSort.waitForExistence(timeout: 5)); titleSort.tap()
        XCTAssertTrue(app.staticTexts["40 artikler"].waitForExistence(timeout: 8))
    }

    private func frame(_ key: String) -> CGRect {
        guard let value = report()[key] as? [String: Double],
              let x = value["x"], let y = value["y"],
              let width = value["width"], let height = value["height"] else {
            XCTFail("Missing native frame: " + key); return .zero
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func assertMiniInsideDetail() {
        wait { !self.frame("detailFrame").isEmpty && !self.frame("miniFrame").isEmpty }
        XCTAssertTrue(frame("detailFrame").insetBy(dx: -1, dy: -1).contains(frame("miniFrame")))
        let pause = app.buttons["podcast.mini.playPause"]
        XCTAssertTrue(pause.isHittable)
        XCTAssertGreaterThanOrEqual(pause.frame.width, 44)
        XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
    }

    private func capture(_ name: String) {
        let pixels = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pixels.name = name; pixels.lifetime = .keepAlways; add(pixels)
        let receipt = XCTAttachment(string: app.staticTexts["list.navigation.state"].value as? String ?? "")
        receipt.name = name + " state"; receipt.lifetime = .keepAlways; add(receipt)
    }

    func testRotationAndSectionSwitchRetainActualSearchAndMiniPlayer() {
        prepareSearch()
        let identity = report()["fixtureIdentity"] as? String
        let episode = report()["episodeID"] as? String
        XCTAssertNotNil(identity); XCTAssertEqual(episode, "local-list-audio")
        assertMiniInsideDetail()
        app.buttons["podcast.mini.playPause"].tap()
        wait { self.report()["pauseActions"] as? Int == 1 && self.report()["playing"] as? Bool == false }
        capture("iPad workspace landscape search")
        XCUIDevice.shared.orientation = .portrait
        wait { self.app.frame.height > self.app.frame.width
            && self.app.textFields["search.controls.query"].value as? String == "Rejse" }
        XCTAssertEqual(app.buttons["search.controls.sort"].value as? String, "Titel A-Å")
        XCTAssertTrue(app.staticTexts["40 artikler"].exists)
        assertMiniInsideDetail()
        XCTAssertEqual(report()["fixtureIdentity"] as? String, identity)
        XCTAssertEqual(report()["episodeID"] as? String, episode)
        XCTAssertEqual(report()["pauseActions"] as? Int, 1)
        XCTAssertEqual(report()["playing"] as? Bool, false)
        capture("iPad workspace portrait search")
        XCUIDevice.shared.orientation = .landscapeLeft
        wait { self.app.frame.width > self.app.frame.height }
        select("categories"); select("search")
        XCTAssertEqual(app.textFields["search.controls.query"].value as? String, "Rejse")
        XCTAssertEqual(app.buttons["search.controls.sort"].value as? String, "Titel A-Å")
        XCTAssertTrue(app.staticTexts["40 artikler"].exists)
        XCTAssertEqual(report()["hasActiveEpisode"] as? Bool, true)
        XCTAssertEqual(report()["fixtureIdentity"] as? String, identity)
        XCTAssertEqual(report()["episodeID"] as? String, episode)
        XCTAssertEqual(report()["playing"] as? Bool, false)
        assertMiniInsideDetail()
        XCTAssertEqual(report()["pauseActions"] as? Int, 1)
        XCTAssertEqual(report()["forwardActions"] as? Int, 0)
        XCTAssertEqual(report()["openActions"] as? Int, 0)
        capture("iPad workspace retained search")
    }

    func testRepeatedHomeSelectionKeepsOtherSectionPathAndPlayback() {
        prepareSearch()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rejse 01")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.isHittable); row.tap()
        wait { self.report()["searchPathCount"] as? Int == 1 }
        capture("iPad workspace search path before Home")
        select("home")
        capture("iPad workspace first Home search path")
        let first = report()["homeStackID"] as? String
        XCTAssertNotNil(first)
        select("home")
        wait { self.report()["homeStackID"] as? String != first }
        capture("iPad workspace repeated Home search path")
        XCTAssertEqual(report()["searchPathCount"] as? Int, 1)
        select("search")
        XCTAssertTrue(app.staticTexts["list.navigation.article"].waitForExistence(timeout: 5))
        XCTAssertEqual(report()["searchPathCount"] as? Int, 1)
        XCTAssertEqual(report()["hasActiveEpisode"] as? Bool, true)
        XCTAssertEqual(report()["pauseActions"] as? Int, 0)
        XCTAssertEqual(report()["forwardActions"] as? Int, 0)
        XCTAssertEqual(report()["openActions"] as? Int, 0)
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        capture("iPad workspace repeated Home preserves search")
    }
    func testPreparationAndDismissalKeepOnlyTheCurrentAccessoryInDetail() {
        assertMiniInsideDetail()
        let identity = report()["fixtureIdentity"] as? String
        app.buttons["ipad.fixture.preparation"].tap()
        wait { self.report()["hasActiveEpisode"] as? Bool == false
            && self.report()["hasPreparation"] as? Bool == true
            && self.frame("miniFrame").isEmpty && !self.frame("preparationFrame").isEmpty }
        XCTAssertTrue(frame("detailFrame").insetBy(dx: -1, dy: -1).contains(frame("preparationFrame")))
        XCTAssertFalse(app.buttons["podcast.mini.playPause"].exists)
        capture("iPad workspace preparation in detail")
        let cancel = app.buttons["Annuller åbning af lyd"]
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        wait { self.report()["hasPreparation"] as? Bool == false && self.frame("preparationFrame").isEmpty }
        XCTAssertTrue(frame("miniFrame").isEmpty)
        XCTAssertFalse(app.buttons["podcast.mini.playPause"].exists)
        XCTAssertEqual(report()["fixtureIdentity"] as? String, identity)
        XCTAssertEqual(report()["openActions"] as? Int, 0)
        XCTAssertEqual(report()["pauseActions"] as? Int, 0)
        capture("iPad workspace no stale accessory")
    }

}
