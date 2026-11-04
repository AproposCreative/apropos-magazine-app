import XCTest
import CoreGraphics

/// Actual history model/binding/notice with manual document measurements and memory storage. No WebKit, KVS, auth or SDK setup.
final class ReadingHistorySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private enum Target: Int, CaseIterable {
        case firebase, owner, unresolved, guest, accountA, accountB, position, playTitle, storageStatus, save, oldSave, failWrites, issue, retry
        var id: String {
            switch self {
            case .firebase: return "history.fixture.firebase"
            case .owner: return "history.fixture.owner"
            case .unresolved: return "history.owner.Uafklaret"
            case .guest: return "history.owner.Gæst"
            case .accountA: return "history.owner.Konto A"
            case .accountB: return "history.owner.Konto B"
            case .position: return "history.fixture.position"
            case .playTitle: return "history.fixture.playTitle"
            case .storageStatus: return "history.fixture.storageStatus"
            case .save: return "history.fixture.save"
            case .oldSave: return "history.fixture.oldSave"
            case .failWrites: return "history.fixture.failWrites"
            case .issue: return "history.issue"
            case .retry: return "history.retry"
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposHistorySmoke"]
        app.launch()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate();app = nil }
    private var form: XCUIElement { app.descendants(matching: .any).matching(identifier: "history.fixture.form").firstMatch }
    private func element(_ target: Target) -> XCUIElement {
        switch target {
        case .unresolved, .guest, .accountA, .accountB, .save, .oldSave, .retry: return app.buttons[target.id]
        case .failWrites: return app.switches[target.id]
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
            format: "label BEGINSWITH %@", "Historikmodel, dokumentbinding og fejlfelt"
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
        XCTFail("History control outside visible viewport: \(target.id)", file: file, line: line)
        return control(row)
    }
    private func assertLabel(_ target: Target, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(target, file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element(target))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line)
    }
    private func setFailure(_ enabled: Bool) {
        let knob = reveal(.failWrites)
        if element(.failWrites).value as? String != (enabled ? "1" : "0") { knob.tap() }
        XCTAssertEqual(element(.failWrites).value as? String, enabled ? "1" : "0")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name;attachment.lifetime = .keepAlways;add(attachment)
    }

    func testOwnersAndCapturedOldScrollRemainIsolated() {
        reveal(.save).tap()
        assertLabel(.position, "Ingen målt fremdrift")
        reveal(.accountA).tap()
        reveal(.save).tap()
        assertLabel(.position, "Målt fremdrift: 45 procent")
        assertLabel(.playTitle, "Artiklen står som læst")
        capture("Læsehistorik — konto A har sin egen historik")
        reveal(.accountB).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Ingen målt fremdrift")
        assertLabel(.playTitle, "Artiklen er ikke i historikken")
        reveal(.save).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Målt fremdrift: 45 procent")
        reveal(.guest).tap()
        assertLabel(.position, "Ingen målt fremdrift")
        reveal(.oldSave).tap()
        assertLabel(.playTitle, "Artiklen er ikke i historikken")
        capture("Læsehistorik — gæst overtager ikke en kontos måling")
        reveal(.accountA).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Målt fremdrift: 45 procent")
        reveal(.unresolved).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Ingen målt fremdrift")
        assertLabel(.firebase, "Firebase: ikke startet")
    }

    func testFailedHistorySaveShowsSharedNoticeAndExplicitOwnerScopedRetry() {
        reveal(.accountA).tap()
        setFailure(true)
        reveal(.save).tap()
        assertLabel(.issue, "Læsehistorikken kunne ikke gemmes. Dine seneste ændringer kan mangle, næste gang du åbner appen.")
        assertLabel(.storageStatus, "Lagring ikke bekræftet")
        reveal(.retry) // Capture the notice itself, including at maximum Dynamic Type.
        capture("Læsehistorik — gemmefejl med synlig forklaring og retry")
        setFailure(false)
        reveal(.retry).tap()
        assertLabel(.storageStatus, "Ændringen er gemt i testens hukommelseslager")
        assertLabel(.position, "Målt fremdrift: 45 procent")
        reveal(.accountB).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Ingen målt fremdrift")
        reveal(.accountA).tap()
        assertLabel(.position, "Målt fremdrift: 45 procent")
        assertLabel(.playTitle, "Artiklen står som læst")
        capture("Læsehistorik — retry gemmer kun den aktive læsers historik")
    }
}
