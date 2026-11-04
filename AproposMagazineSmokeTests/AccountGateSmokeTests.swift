import XCTest
import UIKit

final class AccountGateSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var orientation: UIDeviceOrientation = .unknown
    override func setUpWithError() throws {
        continueAfterFailure = false
        orientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposAccountGateSmoke"]
        if name.contains("SaveSheet") { app.launchArguments.append("-GatingSheet") }
        if name.contains("English") { app.launchArguments.append("-GatingEnglish") }
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["guest.fixture.report"].waitForExistence(timeout: 10))
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = orientation
    }
    private func report() throws -> [String: Any] {
        let raw = try XCTUnwrap(app.staticTexts["guest.fixture.report"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }
    private func capture(_ phase: String) throws {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Account gate original — " + phase; shot.lifetime = .keepAlways; add(shot)
        let data = try JSONSerialization.data(withJSONObject: report(), options: [.sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = "Account gate JSON — " + phase; json.lifetime = .keepAlways; add(json)
    }
    func testGuestInlineDesignAndEmailChoices() throws {
        XCTAssertTrue(app.staticTexts["guestAccount.title"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["guest.fixture.apple"].isHittable)
        XCTAssertTrue(app.buttons["guest.fixture.google"].isHittable)
        XCTAssertTrue(app.buttons["guestAccount.email"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["guestAccount.signIn"].frame.height, 44)
        try capture("minside-guest")
        app.buttons["guestAccount.email"].tap()
        XCTAssertTrue(app.staticTexts["guest.fixture.emailAction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guest.fixture.emailAction"].label, "Opret konto")
        app.buttons["Luk"].tap()
        app.buttons["guestAccount.signIn"].tap()
        XCTAssertTrue(app.staticTexts["guest.fixture.emailAction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["guest.fixture.emailAction"].label, "Log ind")
        XCTAssertEqual(try report()["saved"] as? [String], [])
    }
    func testSaveSheetCancelThenExplicitLoginSavesOnce() throws {
        app.buttons["guest.fixture.save"].tap()
        XCTAssertTrue(app.staticTexts["guestAccount.title"].waitForExistence(timeout: 6))
        XCTAssertEqual(try report()["saved"] as? [String], [])
        try capture("save-sheet")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
        XCTAssertTrue(app.buttons["guest.fixture.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(try report()["pending"] as? Bool, false)
        app.buttons["guest.fixture.save"].tap()
        XCTAssertTrue(app.buttons["guest.fixture.google"].waitForExistence(timeout: 5))
        app.buttons["guest.fixture.google"].tap()
        XCTAssertTrue(app.buttons["guest.fixture.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(try report()["saved"] as? [String], ["gate-article"])
        XCTAssertEqual(try report()["writes"] as? Int, 1)
        XCTAssertEqual(try report()["pending"] as? Bool, false)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
        try capture("explicit-login-one-save")
    }
    func testEnglishGuestInterfaceUsesSelectedLanguage() throws {
        let title = app.staticTexts["guestAccount.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 6))
        XCTAssertEqual(title.label, "We have a point of view.\nFind yours.")
        XCTAssertEqual(app.buttons["guestAccount.email"].label, "Create account with email")
        XCTAssertEqual(app.buttons["guestAccount.signIn"].label, "Already have an account? Sign in")
        XCTAssertFalse(app.staticTexts["Vi har en holdning.\nFå din egen."].exists)
        try capture("english-guest")
    }
    func testLargestTextGuestActionsRemainReachableAndRotation() throws {
        try checkLargestTextGuestActionsAndRotation()
    }
    func testEnglishLargestTextGuestActionsRemainReachableAndRotation() throws {
        XCTAssertEqual(app.staticTexts["guestAccount.title"].label, "We have a point of view.\nFind yours.")
        try checkLargestTextGuestActionsAndRotation()
    }
    private func checkLargestTextGuestActionsAndRotation() throws {
        XCTAssertTrue(app.staticTexts["guestAccount.title"].waitForExistence(timeout: 6))
        try capture("largest-portrait")
        let scroll = app.scrollViews["guestAccount.scroll"]
        for _ in 0..<5 where !app.buttons["guestAccount.email"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.buttons["guestAccount.email"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["guestAccount.email"].frame.height, 44)
        try capture("largest-actions")
        XCUIDevice.shared.orientation = .landscapeLeft
        let settled = expectation(for: NSPredicate { [weak self] _, _ in
            guard let self else { return false }; return self.app.frame.width > self.app.frame.height
        }, evaluatedWith: nil)
        wait(for: [settled], timeout: 8)
        XCTAssertTrue(app.staticTexts["guestAccount.title"].exists)
        try capture("largest-landscape")
    }
}
