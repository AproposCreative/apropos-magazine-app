import XCTest
import CoreGraphics

/// Actual entry/coordinator and shared alert; held memory callbacks only.
final class IncomingLinkSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private enum Target: Int, CaseIterable {
        case firebase, owner, readiness, accountA, accountB, ready, requests, ignored, latest45, latest0, release, article, start
        var id: String {
            switch self {
            case .firebase: return "incoming.fixture.firebase"
            case .owner: return "incoming.fixture.owner"
            case .readiness: return "incoming.fixture.readiness"
            case .accountA: return "incoming.fixture.accountA"
            case .accountB: return "incoming.fixture.accountB"
            case .ready: return "incoming.fixture.ready"
            case .requests: return "incoming.fixture.requests"
            case .ignored: return "incoming.fixture.ignored"
            case .latest45: return "incoming.fixture.latest45"
            case .latest0: return "incoming.fixture.latest0"
            case .release: return "incoming.fixture.release"
            case .article: return "incoming.fixture.article"
            case .start: return "incoming.fixture.start"
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposIncomingLinkSmoke"]
        app.launch()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }
    private var form: XCUIElement { app.descendants(matching: .any).matching(identifier: "incoming.fixture.form").firstMatch }
    private func element(_ target: Target) -> XCUIElement {
        switch target {
        case .accountA, .accountB, .ready, .latest45, .latest0, .release: return app.buttons[target.id]
        default: return app.staticTexts[target.id]
        }
    }
    private var viewport: CGRect {
        CGRect(x: app.frame.minX + 12, y: app.frame.minY + 120, width: max(1, app.frame.width - 24), height: max(1, app.frame.height - 164))
    }
    private func control(_ row: XCUIElement) -> XCUIElement {
        let knob = row.switches.firstMatch
        return knob.exists ? knob : row
    }
    private func anchor() -> Int {
        var nearest: (CGFloat, Int)?
        func consider(_ row: XCUIElement, rank: Int) {
            guard row.exists else { return }
            let frame = control(row).frame
            guard !frame.isEmpty, frame.minX.isFinite, frame.minY.isFinite,
                  frame.width.isFinite, frame.height.isFinite else { return }
            let visible = frame.intersection(viewport)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
            let distance = abs(visible.midY - viewport.midY)
            if nearest == nil || distance < nearest!.0 { nearest = (distance, rank) }
        }
        // The introduction can fill the entire viewport at maximum text size.
        // It is before every target; falling back to an old retry rank here
        // would keep dragging toward the top forever after Form relayout.
        let introduction = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Manuelle opslag i hukommelsen."
        )).firstMatch
        consider(introduction, rank: -1)
        for target in Target.allCases {
            consider(element(target), rank: target.rawValue)
        }
        return nearest?.1 ?? lastRank
    }
    private func scroll(up: Bool) {
        // Full-page flicks can jump over a wrapped row and oscillate at maximum
        // Dynamic Type. Keep each gesture inside the viewport and use a smaller
        // drag; target visibility is still checked with the same strict bounds.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.64 : 0.36))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.36 : 0.64))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    @discardableResult
    private func reveal(_ target: Target, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = element(target)
        for _ in 0..<48 {
            if row.exists {
                let button = control(row), frame = button.frame
                if !frame.isEmpty, frame.midX.isFinite, frame.midY.isFinite {
                    if button.isHittable && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                        lastRank = target.rawValue
                        return button
                    }
                    scroll(up: frame.midY >= viewport.minY)
                    continue
                }
            }
            scroll(up: target.rawValue >= anchor())
        }
        XCTFail("Incoming link control outside visible viewport: \(target.id)", file: file, line: line)
        return control(row)
    }
    private func assertLabel(_ target: Target, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(target, file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element(target))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func dismissMissingAudio() {
        let alert = app.alerts.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Dit link", "Your link")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["Artiklen er åbnet, men der er ingen tilgængelig lyd til den."].exists)
        capture("Link — tydelig artikel uden tilgængelig lyd")
        alert.buttons.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Luk", "Close")).firstMatch.tap()
        XCTAssertFalse(alert.exists)
    }
    func testColdZeroTimestampWaitsForCanonicalAccountAndUIThenShowsDismissibleFallback() {
        assertLabel(.requests, "Startede opslag: 0")
        assertLabel(.owner, "Aktiv læser: Uafklaret")
        assertLabel(.readiness, "UI: ikke klar")
        reveal(.accountA).tap()
        assertLabel(.requests, "Startede opslag: 0")
        reveal(.ready).tap()
        assertLabel(.requests, "Startede opslag: 1")
        assertLabel(.article, "Ingen artikel åbnet")
        reveal(.release).tap()
        dismissMissingAudio()
        assertLabel(.article, "Artikel åbnet: fixture-article")
        assertLabel(.start, "Ønsket lydstart: 0 s")
        assertLabel(.ignored, "Afviste gamle svar: 0")
        assertLabel(.firebase, "Firebase: ikke startet")
        reveal(.start)
        capture("Link — nul er et eksplicit tidspunkt efter kold start")
    }
    func testLatestLinkAndAccountChangeRejectHeldOldCallbacksBeforeExplicitZeroResult() {
        reveal(.accountA).tap(); reveal(.ready).tap()
        assertLabel(.requests, "Startede opslag: 1")
        reveal(.latest45).tap()
        assertLabel(.requests, "Startede opslag: 1")
        reveal(.release).tap()
        assertLabel(.ignored, "Afviste gamle svar: 1")
        assertLabel(.requests, "Startede opslag: 2")
        assertLabel(.article, "Ingen artikel åbnet")
        reveal(.accountB).tap()
        reveal(.latest0).tap()
        reveal(.release).tap()
        assertLabel(.ignored, "Afviste gamle svar: 2")
        assertLabel(.requests, "Startede opslag: 3")
        assertLabel(.owner, "Aktiv læser: Konto B")
        assertLabel(.article, "Ingen artikel åbnet")
        reveal(.release).tap()
        dismissMissingAudio()
        assertLabel(.article, "Artikel åbnet: fixture-article")
        assertLabel(.start, "Ønsket lydstart: 0 s")
        assertLabel(.firebase, "Firebase: ikke startet")
        reveal(.ignored)
        capture("Link — gamle callbacks afvist efter nyt link og kontoskift")
    }
}
