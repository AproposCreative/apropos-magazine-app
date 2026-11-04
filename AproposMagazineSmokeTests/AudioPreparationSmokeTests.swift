import XCTest
import CoreGraphics

final class AudioPreparationSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposAudioAssetSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["audio.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["audio.fixture.firebase"].label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }
    private func scrollTo(_ row: XCUIElement) {
        for _ in 0..<18 {
            let frame = row.frame
            let viewport = app.frame.insetBy(dx: 12, dy: 100)
            if row.isHittable, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) { return }
            app.swipeUp(velocity: .slow)
        }
        XCTFail("Control must be visible before use")
    }
    private func start() {
        let button = app.buttons["audio.fixture.start"]
        scrollTo(button); button.tap()
        XCTAssertTrue(app.staticTexts["podcast.preparation.heading"].waitForExistence(timeout: 3))
    }
    private func cancel() {
        let button = app.buttons["podcast.preparation.cancel"]
        scrollTo(button); capture("Lydkontrol — synlig annullering")
        button.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["podcast.preparation.heading"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed)
    }
    private func assertLabel(_ id: String, _ value: String) {
        let row = app.staticTexts[id]; scrollTo(row); XCTAssertEqual(row.label, value)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPendingAudioKeepsFullTitleAndCanBeCancelledWithoutPlayback() {
        start()
        let title = app.staticTexts["podcast.preparation.title"]
        XCTAssertTrue(title.label.hasPrefix("Første kontrol:"))
        XCTAssertTrue(title.label.hasSuffix("de steder, vi mødes"))
        capture("Lydkontrol — ærlig ventetilstand og fuld titel")
        cancel()
        assertLabel("audio.fixture.cancelled", "Annulleringer: 1")
        assertLabel("audio.fixture.accepted", "Godkendte lokale svar: 0")
    }
    func testLateCancelledReplyCannotFinishOrDismissNewPreparation() {
        start(); cancel(); start()
        let release = app.buttons["audio.fixture.release"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: release)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(release.isHittable); release.tap()
        XCTAssertEqual(app.staticTexts["audio.fixture.liveIgnored"].label, "Afvist: 1")
        XCTAssertTrue(app.staticTexts["podcast.preparation.title"].label.hasPrefix("Ny kontrol:"))
        capture("Lydkontrol — gammelt svar afvist mens ny kontrol bevares")
        cancel()
        assertLabel("audio.fixture.cancelled", "Annulleringer: 2")
        assertLabel("audio.fixture.accepted", "Godkendte lokale svar: 0")
    }
}
