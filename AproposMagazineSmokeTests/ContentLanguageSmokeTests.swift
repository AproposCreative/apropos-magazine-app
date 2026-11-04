import XCTest
import UIKit

/// Actual Settings language picker and Search pipeline. Local article text only;
/// this never claims a CMS deployment, real reader, login or network acceptance.
final class ContentLanguageSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var originalOrientation: UIDeviceOrientation = .unknown
    private let da = "En dansk kulturfortælling"
    private let en = "An English culture story"

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposContentLanguageSmoke", "-ResetContentLanguageFixture"]
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["language.fixture.report"].waitForExistence(timeout: 10))
        let loaded = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return (try? self.report()["loadState"] as? String) == "loaded"
        }
        let ready = expectation(for: loaded, evaluatedWith: nil)
        wait(for: [ready], timeout: 8)
        XCTAssertEqual(try report()["englishSourceEnabled"] as? Bool, true)
        XCTAssertEqual(try report()["sourceLanguages"] as? [String], ["da", "en"])
        XCTAssertEqual(try report()["decodedFailureCount"] as? Int, 0)
        XCTAssertEqual(try report()["realCMSRead"] as? Bool, false)
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }
    override func tearDownWithError() throws {
        app?.terminate(); app = nil
        XCUIDevice.shared.orientation = originalOrientation
    }
    private func report() throws -> [String: Any] {
        let raw = try XCTUnwrap(app.staticTexts["language.fixture.report"].value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }
    private func openSettings() {
        let button = app.buttons["language.fixture.settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.articleLanguage").firstMatch.waitForExistence(timeout: 5))
    }
    private func select(_ language: String) {
        let picker = app.descendants(matching: .any).matching(identifier: "settings.articleLanguage").firstMatch
        XCTAssertTrue(picker.isHittable); picker.tap()
        let option = app.buttons[language]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
    }
    private func closeSettings() { app.buttons["language.fixture.closeSettings"].tap() }
    private func capture(_ phase: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let original = XCTAttachment(screenshot: screenshot)
        original.name = "Artikelsprog original — " + phase
        original.lifetime = .keepAlways; add(original)
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale
        let normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let shot = XCTAttachment(image: normalized); shot.name = "Artikelsprog — " + phase
        shot.lifetime = .keepAlways; add(shot)
        let receipt = XCTAttachment(string: String(data: try JSONSerialization.data(withJSONObject: report(), options: [.sortedKeys]), encoding: .utf8)!)
        receipt.name = "Artikelsprog JSON — " + phase; receipt.lifetime = .keepAlways; add(receipt)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Artikelsprog AX — " + phase; tree.lifetime = .keepAlways; add(tree)
    }

    func testLanguageChoiceFiltersActualSearchAndSurvivesColdLaunch() throws {
        XCTAssertTrue(app.staticTexts[da].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[en].exists)
        try capture("dansk")
        openSettings(); select("English")
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 5))
        try capture("indstillinger-engelsk"); closeSettings()
        XCTAssertTrue(app.staticTexts[en].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[da].exists)
        XCTAssertEqual(try report()["catalogIDs"] as? [String], ["0123456789abcdef01234567", "en_0123456789abcdef01234567"])
        app.staticTexts[en].tap()
        XCTAssertTrue(app.staticTexts["language.fixture.body"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["language.fixture.body"].label, "This is the English article body.")
        try capture("engelsk-artikel")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-ResetContentLanguageFixture" }
        app.launch()
        XCTAssertTrue(app.staticTexts[en].waitForExistence(timeout: 8))
        XCTAssertEqual(try report()["storedLanguage"] as? String, "en")
        XCTAssertEqual(try report()["sourceLanguages"] as? [String], ["da", "en"])
        XCTAssertEqual(try report()["loadState"] as? String, "loaded")
        XCTAssertFalse(app.staticTexts[da].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return self.app.frame.width > self.app.frame.height
        }
        let settled = expectation(for: landscape, evaluatedWith: nil)
        wait(for: [settled], timeout: 8)
        XCTAssertTrue(app.staticTexts[en].waitForExistence(timeout: 5))
        try capture("engelsk-kold-rotation")
        openSettings(); select("Dansk"); closeSettings()
        XCTAssertTrue(app.staticTexts[da].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[en].exists)
        try capture("tilbage-dansk")
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }

    func testLargestTextEnglishEmptyNeverFallsBackToDanish() throws {
        XCTAssertEqual(try report()["accessibilityText"] as? Bool, true)
        openSettings(); select("English")
        try capture("stoerste-tekst-valg")
        let remove = app.buttons["language.fixture.removeEnglish"]
        for _ in 0..<4 where !remove.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(remove.isHittable); remove.tap(); closeSettings()
        XCTAssertTrue(app.staticTexts["No articles found"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts[da].exists)
        XCTAssertFalse(app.staticTexts[en].exists)
        XCTAssertEqual(try report()["visibleIDs"] as? [String], [])
        XCTAssertEqual((try report()["catalogIDs"] as? [String])?.count, 1)
        XCTAssertEqual(try report()["sourceLanguages"] as? [String], ["da", "en"])
        XCTAssertEqual(try report()["loadState"] as? String, "loaded")
        try capture("stoerste-tekst-engelsk-tom")
        openSettings(); select("Dansk"); closeSettings()
        XCTAssertTrue(app.staticTexts[da].waitForExistence(timeout: 8))
        try capture("stoerste-tekst-dansk-bevaret")
        XCTAssertEqual(try report()["firebaseStarted"] as? Bool, false)
    }
}
