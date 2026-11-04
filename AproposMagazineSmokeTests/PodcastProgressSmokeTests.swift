import XCTest
import CoreGraphics

/// Real progress model/notice, memory storage only. No audio, auth or SDK setup.
final class PodcastProgressSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private enum Target: Int, CaseIterable {
        case firebase, owner, queueSelection, unresolved, guest, accountA, accountB, position, playTitle, storageStatus, save, oldSave, failWrites, issue, retry
        var id: String {
            switch self {
            case .firebase: return "progress.fixture.firebase"
            case .owner: return "progress.fixture.owner"
            case .queueSelection: return "progress.fixture.queueSelection"
            case .unresolved: return "progress.owner.Uafklaret"
            case .guest: return "progress.owner.Gæst"
            case .accountA: return "progress.owner.Konto A"
            case .accountB: return "progress.owner.Konto B"
            case .position: return "progress.fixture.position"
            case .playTitle: return "progress.fixture.playTitle"
            case .storageStatus: return "progress.fixture.storageStatus"
            case .save: return "progress.fixture.save"
            case .oldSave: return "progress.fixture.oldSave"
            case .failWrites: return "progress.fixture.failWrites"
            case .issue: return "progress.issue"
            case .retry: return "progress.retry"
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposProgressSmoke"]
        app.launch()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate();app = nil }
    private var form: XCUIElement { app.descendants(matching: .any).matching(identifier: "progress.fixture.form").firstMatch }
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
        for target in Target.allCases {
            let row = element(target)
            guard row.exists else { continue }
            let frame = control(row).frame
            guard !frame.isEmpty, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            let distance = abs(frame.midY - viewport.midY)
            if nearest == nil || distance < nearest!.0 { nearest = (distance, target.rawValue) }
        }
        return nearest?.1 ?? lastRank
    }
    @discardableResult
    private func reveal(_ target: Target, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = element(target)
        for _ in 0..<28 {
            if row.exists {
                let button = control(row), frame = button.frame
                if !frame.isEmpty, frame.midX.isFinite, frame.midY.isFinite {
                    if button.isHittable && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                        lastRank = target.rawValue
                        return button
                    }
                    if frame.midY < viewport.minY || frame.minY < viewport.minY { form.swipeDown() }
                    else { form.swipeUp() }
                    continue
                }
            }
            if target.rawValue < anchor() { form.swipeDown() } else { form.swipeUp() }
        }
        XCTFail("Progress control outside visible viewport: \(target.id)", file: file, line: line)
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

    func testAccountSwitchHidesOtherReadersResumeAndRejectsOldWrite() {
        reveal(.save).tap()
        assertLabel(.position, "Ingen gemt position")
        reveal(.accountA).tap()
        reveal(.save).tap()
        assertLabel(.position, "Gemt position: 42 sekunder")
        assertLabel(.playTitle, "Fortsæt")
        capture("Lytteposition — konto A kan fortsætte")
        reveal(.accountB).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Ingen gemt position")
        assertLabel(.playTitle, "Lyt")
        capture("Lytteposition — konto B overtager ikke A")
        reveal(.save).tap()
        reveal(.oldSave).tap()
        assertLabel(.position, "Gemt position: 42 sekunder")
        reveal(.guest).tap()
        assertLabel(.position, "Ingen gemt position")
        reveal(.accountA).tap()
        assertLabel(.position, "Gemt position: 42 sekunder")
    }

    func testWriteFailureShowsTruthfulNoticeAndExplicitRetryPersistsOnlyActiveReader() {
        reveal(.accountA).tap()
        setFailure(true)
        reveal(.save).tap()
        assertLabel(.issue, "Lyttepositionen kunne ikke gemmes. Den kan mangle næste gang du åbner appen.")
        capture("Lytteposition — gemmefejl med ærlig status og retry")
        setFailure(false)
        reveal(.retry).tap()
        assertLabel(.storageStatus, "Lagring bekræftet i hukommelsen")
        assertLabel(.position, "Gemt position: 42 sekunder")
        reveal(.accountB).tap()
        assertLabel(.position, "Ingen gemt position")
        reveal(.accountA).tap()
        assertLabel(.position, "Gemt position: 42 sekunder")
        capture("Lytteposition — retry gemmer hos den rigtige konto")
    }

    func testQueueUsesCompactTopSpacingShowsCurrentEpisodeAndSelectsAnotherEpisode() {
        app.buttons["progress.fixture.openQueue"].tap()
        let queue = app.descendants(matching: .any).matching(identifier: "podcast.queue.list").firstMatch
        XCTAssertTrue(queue.waitForExistence(timeout: 5))
        let navigationBar = app.navigationBars["Kø"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let firstEpisode = app.buttons["podcast.queue.episode.queue-one"]
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 5))
        XCTAssertTrue(firstEpisode.isHittable)
        // Measure the first row's button content against the actual navigation
        // bar, so the test catches a reintroduced empty grouped-list header.
        let topGap = firstEpisode.frame.minY - navigationBar.frame.maxY
        let geometry = XCTAttachment(string: "Queue first-row gap below navigation: \(topGap) pt")
        geometry.name = "Queue top spacing"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertGreaterThanOrEqual(topGap, 0, "The first row must not overlap the navigation bar")
        XCTAssertLessThanOrEqual(topGap, 16, "Unnecessary space below the queue title: \(topGap) pt")
        capture("Kø — første række ved åbning i medium højde")

        let currentEpisode = app.buttons["podcast.queue.episode.queue-three"]
        let badge = app.descendants(matching: .any).matching(identifier: "podcast.queue.nowPlaying").firstMatch
        for _ in 0..<12 {
            if badge.exists && badge.isHittable && queue.frame.contains(CGPoint(x: badge.frame.midX, y: badge.frame.midY)) { break }
            queue.swipeUp()
        }
        XCTAssertTrue(currentEpisode.exists)
        XCTAssertTrue(badge.exists)
        XCTAssertTrue(badge.isHittable)
        XCTAssertEqual(badge.label, "Afspiller")
        capture("Kø — aktuel episode med læsbart Afspiller-mærke")

        let selectedEpisode = app.buttons["podcast.queue.episode.queue-two"]
        for _ in 0..<12 {
            if selectedEpisode.exists && selectedEpisode.isHittable && queue.frame.contains(CGPoint(x: selectedEpisode.frame.midX, y: selectedEpisode.frame.midY)) { break }
            queue.swipeDown()
        }
        XCTAssertTrue(selectedEpisode.isHittable)
        selectedEpisode.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: queue)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        assertLabel(.queueSelection, "Valgt episode: queue-two")
        assertLabel(.firebase, "Firebase: ikke startet")
    }
}
