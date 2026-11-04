import XCTest

final class ArticleListenHeroSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private struct Rect: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Report: Decodable {
        let actionCount: Int, selectedEpisodeID: String, catalogCount: Int
        let managerInvoked: Bool, audioStarted: Bool, firebaseStarted: Bool
        let environmentAccessibility: Bool, systemAccessibility: Bool, systemCategory: String
        let chromeIsLocalFixture: Bool
        let imageScenario: String, imagePhase: String
        let imageSeedReady: Bool, imageLoadedFromSeededCache: Bool, imageLoadingLocalFile: Bool
        let imageLoadedCount: Int, imageFailedCount: Int, imageDownloadCount: Int
        let imagePixelWidth: Double, imagePixelHeight: Double
        let frames: [String: Rect]
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testNormalReaderListenTapAndSixteenPointHeroGap() throws {
        try exercise(category: "UICTContentSizeCategoryL", accessibility: false)
    }

    func testAccessibilityReaderListenTapAndSixteenPointHeroGap() throws {
        try exercise(category: "UICTContentSizeCategoryAccessibilityXXXL", accessibility: true)
    }

    func testLoadedPortraitHeroDoesNotConsumeListenCoordinateTap() throws {
        try exerciseLoadedHero(scenario: "loadedPortrait", width: 600, height: 900)
    }

    func testLoadedLandscapeHeroDoesNotConsumeListenCoordinateTap() throws {
        try exerciseLoadedHero(scenario: "loadedLandscape", width: 900, height: 600)
    }

    func testAccessibilityLoadedPortraitHeroDoesNotConsumeListenCoordinateTap() throws {
        try exerciseLoadedHero(scenario: "loadedPortrait", width: 600, height: 900,
            category: "UICTContentSizeCategoryAccessibilityXXXL", accessibility: true)
    }

    private func report() throws -> Report {
        let raw = try XCTUnwrap(app.staticTexts["listenHero.report"].value as? String)
        return try JSONDecoder().decode(Report.self, from: Data(raw.utf8))
    }

    private func frame(_ key: String, _ report: Report) throws -> CGRect {
        try XCTUnwrap(report.frames[key], "Missing actual layout: \(key)").frame
    }

    private func capture(_ name: String) throws {
        let metadata = XCTAttachment(string: try XCTUnwrap(app.staticTexts["listenHero.report"].value as? String))
        metadata.name = name + " — rendered hero/chrome/viewport and local action"
        metadata.lifetime = .keepAlways; add(metadata)
        let button = app.buttons["reader.listen"]
        let native = XCTAttachment(string: "Native Button frame: \(button.frame)\nEnabled: \(button.isEnabled)\nHittable: \(button.isHittable)\n\(app.debugDescription)")
        native.name = name + " — native control frame and accessibility tree"
        native.lifetime = .keepAlways; add(native)
        let pixels = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pixels.name = name; pixels.lifetime = .keepAlways; add(pixels)
    }

    private func revealListen() throws {
        let button = app.buttons["reader.listen"]
        for _ in 0..<8 {
            let value = try report(), viewport = try frame("viewport", value)
            let chrome = try frame("chrome", value)
            let top = max(viewport.minY, chrome.maxY) + 8, bottom = viewport.maxY - 8
            let target = button.frame
            if target.minY >= top && target.maxY <= bottom { return }
            let upward = target.maxY > bottom
            let excess = upward ? target.maxY - bottom : top - target.minY
            let distance = min((bottom - top) / 2, max(50, excess + 12))
            let center = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: viewport.midX, dy: center + (upward ? distance / 2 : -distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: viewport.midX, dy: center + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func exercise(category: String, accessibility: Bool) throws {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderSmoke", "-ReaderListenHeroSmoke",
                               "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        XCTAssertTrue(app.staticTexts["listenHero.report"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let value = try? self?.report() else { return false }
            return value.catalogCount == 1 && ["hero", "chrome", "viewport"].allSatisfy { value.frames[$0] != nil }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        try capture("\(category) — initial shared reader subtree")
        try revealListen()
        try capture("\(category) — before the single native Listen tap")

        let before = try report(), button = app.buttons["reader.listen"], hit = button.frame
        let viewport = try frame("viewport", before), chrome = try frame("chrome", before)
        XCTAssertEqual(before.environmentAccessibility, accessibility)
        XCTAssertEqual(before.systemAccessibility, accessibility)
        XCTAssertEqual(before.systemCategory, category)
        XCTAssertFalse(before.firebaseStarted)
        XCTAssertEqual(before.actionCount, 0)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThanOrEqual(hit.height, 44 - 0.5)
        XCTAssertGreaterThanOrEqual(hit.minY, max(viewport.minY, chrome.maxY) - 0.5)
        XCTAssertLessThanOrEqual(hit.maxY, viewport.maxY + 0.5)
        XCTAssertFalse(hit.intersects(chrome.insetBy(dx: 0.5, dy: 0.5)))
        button.tap()

        let acted = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            (try? self?.report().actionCount) == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [acted], timeout: 5), .completed)
        try capture("\(category) — actual ArticleListenAction callback after tap")
        let after = try report()
        XCTAssertEqual(after.actionCount, 1)
        XCTAssertEqual(after.selectedEpisodeID, "listen-hero-local-recording")
        XCTAssertFalse(after.managerInvoked, "This native probe does not initialize the AVPlayer manager")
        XCTAssertFalse(after.audioStarted)
        XCTAssertFalse(after.firebaseStarted)
        XCTAssertTrue(after.chromeIsLocalFixture)
        // Keep the desired spacing assertion last so a red baseline retains
        // actual pixels, hit-area checks and the real shared button action.
        let gap = try frame("hero", before).minY - hit.maxY
        XCTAssertEqual(gap, 16, accuracy: 0.5, "Only one 16-point gap should separate the real button hit area and hero")
    }

    private func exerciseLoadedHero(scenario: String, width: Double, height: Double,
                                    category: String = "UICTContentSizeCategoryL", accessibility: Bool = false) throws {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderSmoke", "-ReaderListenHeroSmoke",
                               "-ReaderListenHeroImage", scenario,
                               "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        XCTAssertTrue(app.staticTexts["listenHero.report"].waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let value = try? self?.report() else { return false }
            return value.catalogCount == 1 && value.imagePhase == "loaded" && value.imageLoadedCount > 0
                && ["hero", "chrome", "viewport"].allSatisfy { value.frames[$0] != nil }
        }, object: nil)
        let loadedResult = XCTWaiter.wait(for: [loaded], timeout: 12)
        try capture("\(scenario) — actual PreparedArticleImage after local loading")
        XCTAssertEqual(loadedResult, .completed, "The real image loader must finish before probing its hit area")
        try revealListen()
        try capture("\(scenario) — before the single coordinate Listen tap")

        let before = try report(), button = app.buttons["reader.listen"], hit = button.frame
        let beforeHittable = button.isHittable
        let hitObservation = XCTAttachment(string: "Before the single coordinate tap: hittable=\(beforeHittable)")
        hitObservation.name = "\(scenario) — captured pre-tap hittability"
        hitObservation.lifetime = .keepAlways; add(hitObservation)
        let hero = try frame("hero", before), viewport = try frame("viewport", before)
        let chrome = try frame("chrome", before)
        XCTAssertEqual(before.imageScenario, scenario)
        XCTAssertTrue(before.imageSeedReady)
        XCTAssertEqual(before.imagePixelWidth, width)
        XCTAssertEqual(before.imagePixelHeight, height)
        XCTAssertEqual(before.imagePhase, "loaded")
        XCTAssertGreaterThan(before.imageLoadedCount, 0)
        XCTAssertTrue(before.imageLoadingLocalFile)
        XCTAssertTrue(before.imageLoadedFromSeededCache, "The fallback file cannot stand in for a resolved offline cache image")
        XCTAssertEqual(before.imageFailedCount, 0)
        XCTAssertEqual(before.imageDownloadCount, 0)
        XCTAssertEqual(before.systemCategory, category)
        XCTAssertEqual(before.environmentAccessibility, accessibility)
        XCTAssertEqual(before.systemAccessibility, accessibility)
        XCTAssertFalse(before.firebaseStarted)
        XCTAssertFalse(before.managerInvoked)
        XCTAssertFalse(before.audioStarted)
        XCTAssertEqual(before.actionCount, 0)
        XCTAssertTrue(button.isEnabled)
        XCTAssertGreaterThanOrEqual(hit.height, 44 - 0.5)
        XCTAssertGreaterThanOrEqual(hit.minY, max(viewport.minY, chrome.maxY) - 0.5)
        XCTAssertLessThanOrEqual(hit.maxY, viewport.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(hero.minY, hit.maxY - 0.5)
        XCTAssertFalse(hero.intersects(hit), "The visible hero must not overlap the native button frame")
        XCTAssertFalse(hit.intersects(chrome.insetBy(dx: 0.5, dy: 0.5)))

        // One physical coordinate tap: accessibility activation must not bypass
        // a loaded image that erroneously owns this visible button's hit point.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: hit.midX, dy: hit.midY)).tap()
        let acted = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            (try? self?.report().actionCount) == 1
        }, object: nil)
        let actionResult = XCTWaiter.wait(for: [acted], timeout: 5)
        try capture("\(scenario) — after the single coordinate Listen tap")
        XCTAssertTrue(beforeHittable)
        XCTAssertEqual(actionResult, .completed, "The loaded image must not consume the Listen coordinate tap")
        let after = try report()
        XCTAssertEqual(after.actionCount, 1)
        XCTAssertEqual(after.selectedEpisodeID, "listen-hero-local-recording")
        XCTAssertEqual(after.imagePhase, "loaded")
        XCTAssertTrue(after.imageLoadedFromSeededCache)
        XCTAssertEqual(after.imageDownloadCount, 0)
        XCTAssertFalse(after.firebaseStarted)
        XCTAssertFalse(after.managerInvoked)
        XCTAssertFalse(after.audioStarted)
    }
}
