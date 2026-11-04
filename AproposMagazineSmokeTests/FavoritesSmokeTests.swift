import XCTest
import CoreGraphics

/// Actual favorites model/offline access/shared feedback; memory data only.
final class FavoritesSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private enum Target: Int, CaseIterable {
        case firebase, unresolved, guest, accountA, accountB, owner, count, offline, save, download, oldDownload, failWrites, storage, cloudControls, pending, recovery, stages, remove, restore, completeDrain, completeFavorite, completeProfile, confirmServer, issue, retry
        var id: String {
            switch self {
            case .firebase: return "favorites.fixture.firebase"
            case .unresolved: return "favorites.owner.Uafklaret"
            case .guest: return "favorites.owner.Gæst"
            case .accountA: return "favorites.owner.Konto A"
            case .accountB: return "favorites.owner.Konto B"
            case .owner: return "favorites.fixture.owner"
            case .count: return "favorites.fixture.count"
            case .offline: return "favorites.fixture.offline"
            case .save: return "favorites.fixture.save"
            case .download: return "favorites.fixture.download"
            case .oldDownload: return "favorites.fixture.oldDownload"
            case .failWrites: return "favorites.fixture.failWrites"
            case .storage: return "favorites.fixture.storage"
            case .cloudControls: return "favorites.fixture.cloudControls"
            case .pending: return "favorites.fixture.pending"
            case .recovery: return "favorites.fixture.recovery"
            case .stages: return "favorites.fixture.stages"
            case .remove: return "favorites.fixture.remove"
            case .restore: return "favorites.fixture.restore"
            case .completeDrain: return "favorites.fixture.completeDrain"
            case .completeFavorite: return "favorites.fixture.completeFavorite"
            case .completeProfile: return "favorites.fixture.completeProfile"
            case .confirmServer: return "favorites.fixture.confirmServer"
            case .issue: return "favorites.issue"
            case .retry: return "favorites.retry"
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposFavoritesSmoke"]
        app.launch()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate();app = nil }
    private var form: XCUIElement { app.descendants(matching: .any).matching(identifier: "favorites.fixture.form").firstMatch }
    private func element(_ target: Target) -> XCUIElement {
        switch target {
        case .unresolved, .guest, .accountA, .accountB, .save, .download, .oldDownload, .cloudControls, .remove, .restore, .completeDrain, .completeFavorite, .completeProfile, .confirmServer, .retry: return app.buttons[target.id]
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
            format: "label BEGINSWITH %@", "Favoritmodel, offlineadgang og fejlfelt"
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
        XCTFail("Favorites control outside visible viewport: \(target.id)", file: file, line: line)
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

    func testOwnerMembershipAndDelayedOfflineDownloadStayIsolated() {
        reveal(.save).tap()
        assertLabel(.count, "Gemte artikler: 0")
        reveal(.accountA).tap()
        reveal(.save).tap()
        assertLabel(.count, "Gemte artikler: 1")
        assertLabel(.offline, "Ingen ejet offlineartikel")
        reveal(.accountB).tap()
        assertLabel(.count, "Gemte artikler: 0")
        reveal(.save).tap()
        reveal(.oldDownload).tap()
        assertLabel(.count, "Gemte artikler: 1")
        assertLabel(.offline, "Ingen ejet offlineartikel")
        capture("Favoritter — gammel A-download giver ikke B adgang")
        reveal(.download).tap()
        assertLabel(.offline, "Offlineartikel tilgængelig")
        reveal(.guest).tap()
        reveal(.oldDownload).tap()
        assertLabel(.count, "Gemte artikler: 0")
        assertLabel(.offline, "Ingen ejet offlineartikel")
        capture("Favoritter — gæst overtager ikke kontoens gemte valg")
        reveal(.accountA).tap()
        assertLabel(.count, "Gemte artikler: 1")
        // Shared public bytes may be reused, only with A's restored membership.
        assertLabel(.offline, "Offlineartikel tilgængelig")
        reveal(.unresolved).tap()
        reveal(.oldDownload).tap()
        assertLabel(.count, "Gemte artikler: 0")
        assertLabel(.offline, "Ingen ejet offlineartikel")
        assertLabel(.firebase, "Firebase: ikke startet")
    }
    func testFailedSaveRetainsChoiceAndShowsSharedExplicitRetry() {
        reveal(.guest).tap()
        setFailure(true)
        reveal(.save).tap()
        assertLabel(.count, "Gemte artikler: 1")
        assertLabel(.storage, "Lagring ikke bekræftet")
        assertLabel(.issue, "Ændringerne kunne ikke gemmes på denne enhed. De kan mangle, næste gang du åbner appen. Prøv igen.")
        reveal(.retry)
        capture("Favoritter — gemmefejl med tydelig scoped retry")
        setFailure(false)
        reveal(.retry).tap()
        assertLabel(.storage, "Gemt i testens hukommelseslager")
        assertLabel(.count, "Gemte artikler: 1")
        reveal(.accountB).tap()
        assertLabel(.count, "Gemte artikler: 0")
        reveal(.guest).tap()
        assertLabel(.count, "Gemte artikler: 1")
        capture("Favoritter — genindlæst fra gæstens eget lager")
    }
    func testDurableRemovalRestoresPendingAndWaitsForBothReceiptsAndServerProof() {
        reveal(.accountA).tap();reveal(.save).tap()
        assertLabel(.count, "Gemte artikler: 1")
        reveal(.cloudControls).tap();assertLabel(.pending, "Ændringer i kø: 1")
        reveal(.remove).tap();assertLabel(.count, "Gemte artikler: 0")
        reveal(.restore).tap();assertLabel(.pending, "Ændringer i kø: 1")
        assertLabel(.recovery, "Recovery venter: 1")
        assertLabel(.issue, "Dine valg afventer synkronisering.")
        capture("Favoritter — fjernelse bevaret efter lokal recovery")
        reveal(.completeDrain).tap();assertLabel(.stages, "Favorit venter: 1, profil venter: 0")
        XCTAssertEqual(element(.stages).value as? String, "Lokal profil: ikke indlæst")
        reveal(.completeFavorite).tap();assertLabel(.stages, "Favorit venter: 0, profil venter: 1")
        assertLabel(.pending, "Ændringer i kø: 1")
        reveal(.completeProfile).tap();assertLabel(.stages, "Favorit venter: 0, profil venter: 0")
        XCTAssertEqual(element(.stages).value as? String, "Lokal profil: ikke indlæst")
        assertLabel(.pending, "Ændringer i kø: 1")
        assertLabel(.issue, "Ændringer afventer bekræftelse. Dine valg vises her imens.")
        capture("Favoritter — begge kvitteringer venter på serverliste")
        reveal(.confirmServer).tap();assertLabel(.pending, "Ændringer i kø: 0")
        assertLabel(.count, "Gemte artikler: 0")
        assertLabel(.storage, "Gemt i testens hukommelseslager")
        assertLabel(.firebase, "Firebase: ikke startet")
    }

}
