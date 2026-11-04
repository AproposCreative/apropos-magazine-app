import UIKit
import XCTest

/// Actual FavoritesNotice in the production Min side pager. The model receives
/// real metadata snapshots and journal callbacks; all transport/storage is memory.
final class FavoritesNoticeSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposNotificationInboxSmoke", "-AproposFavoritesNoticeSmoke"]
        app.launch()
        wait("async recovery and controls ready") {
            guard let state = try? self.notice(), let root = try? self.root(),
                  let frames = root["frames"] as? [String: [String: Double]] else { return false }
            return state["fixtureControlsReady"] as? Bool == true && state["modelState"] as? String == "ready"
                && self.app.staticTexts["favorites.notice.fixture.ready"].label == "Lokale kontroller klar"
                && (frames["favorites.firstRow"]?["height"] ?? 0) > 0
        }
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(try notice()["fixtureIssue"] as? String, "")
        XCTAssertEqual(app.buttons["minside.page.saved"].value as? String, "Valgt")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func root() throws -> [String: Any] {
        let report = app.staticTexts["notifications.fixture.report"]
        let data = try XCTUnwrap(report.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func notice() throws -> [String: Any] {
        try XCTUnwrap(root()["notice"] as? [String: Any])
    }
    private func capture(_ phase: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Favorites notice — \(phase)"; shot.lifetime = .keepAlways; add(shot)
        if let state = try? root(), let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = "Favorites notice receipt — \(phase)"; receipt.lifetime = .keepAlways; add(receipt)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Favorites notice AX — \(phase)"; tree.lifetime = .keepAlways; add(tree)
    }
    private func wait(_ phase: String, _ check: @escaping () -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in check() }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        if result != .completed { capture("failed wait " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }
    private func tap(_ name: String) {
        let button = app.buttons["favorites.notice.fixture." + name]
        XCTAssertTrue(button.exists && button.isHittable); button.tap()
    }
    private func tapPage(_ page: Int) throws {
        let button = app.buttons[page == 0 ? "minside.page.saved" : "minside.page.messages"]
        let frames = try XCTUnwrap(root()["frames"] as? [String: [String: Double]])
        let value = try XCTUnwrap(frames["minside.header"])
        let header = CGRect(x: try XCTUnwrap(value["x"]), y: try XCTUnwrap(value["y"]),
            width: try XCTUnwrap(value["width"]), height: try XCTUnwrap(value["height"]))
        let visible = button.frame.intersection(header).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 43.5); XCTAssertGreaterThanOrEqual(visible.height, 44)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }
    private func assertMembership(_ state: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state["memberIDs"] as? [String], ["saved-culture", "saved-film", "saved-music"], file: file, line: line)
        XCTAssertEqual(state["pendingIDs"] as? [String], [], file: file, line: line)
        XCTAssertEqual(state["membershipTicketsCurrent"] as? Bool, true, file: file, line: line)
    }

    func testFourShortJournalCyclesDoNotRenderNoticeOrMoveSavedRows() throws {
        capture("ready before four real short journal writes")
        tap("short")
        wait("four actual cache and confirmed journal cycles completed") {
            guard let state = try? self.notice() else { return false }
            return state["phase"] as? String == "short-complete" && state["shortCycles"] as? Int == 4
                && state["modelState"] as? String == "ready" && state["heldWrites"] as? Int == 0
        }
        let state = try notice()
        // Capture before the no-flash assertions: the old policy's transient
        // actual onAppear/onDisappear and row movement remain in the red run.
        capture("all actual lifecycle events and saved-row Y positions after four writes")
        XCTAssertEqual(state["modelPendingTransitions"] as? Int, 4)
        XCTAssertEqual(state["metadataUpdates"] as? Int, 8)
        XCTAssertEqual(state["noticeAppearances"] as? Int, 0)
        XCTAssertEqual(state["noticeVisible"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["favorites.issue"].exists)
        let ys = try XCTUnwrap(state["firstRowYs"] as? [Double])
        XCTAssertFalse(ys.isEmpty)
        XCTAssertLessThanOrEqual((ys.max() ?? 0) - (ys.min() ?? 0), 1, "No actual saved-row jump during transient writes")
        assertMembership(state)
        XCTAssertEqual(state["serverConfirmed"] as? Bool, true)
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }

    private func observeRealTime(_ seconds: TimeInterval) {
        let elapsed = expectation(description: "bounded real lifecycle observation")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: seconds + 2), .completed)
    }
    private func waitForResolved() {
        wait("real held journal callbacks resolved") {
            guard let state = try? self.notice() else { return false }
            return state["modelState"] as? String == "ready" && state["heldWrites"] as? Int == 0
                && state["noticeVisible"] as? Bool == false
        }
    }
    private func assertNoResurrection(_ phase: String) throws {
        let appearances = try XCTUnwrap(notice()["noticeAppearances"] as? Int)
        observeRealTime(0.85)
        let state = try notice()
        capture(phase)
        XCTAssertEqual(state["noticeAppearances"] as? Int, appearances)
        XCTAssertEqual(state["noticeVisible"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["favorites.issue"].exists)
        assertMembership(state)
    }
    private func assertSustainedDelay() throws {
        wait("generic pending appears while real metadata revisions continue") {
            guard let state = try? self.notice() else { return false }
            return state["modelState"] as? String == "pending" && state["noticeVisible"] as? Bool == true
                && state["phase"] as? String == "sustained-running" && (state["metadataUpdates"] as? Int ?? 0) >= 5
        }
        let state = try notice()
        capture("actual sustained pending card under repeated model revisions")
        let events = try XCTUnwrap(state["visibilityEvents"] as? [[String: Any]])
        let appearance = try XCTUnwrap(events.first { $0["visible"] as? Bool == true })
        let delay = try XCTUnwrap(appearance["afterPending"] as? Double)
        XCTAssertGreaterThanOrEqual(delay, 0.55)
        XCTAssertEqual(appearance["state"] as? String, "pending")
        XCTAssertEqual(state["noticeAppearances"] as? Int, 1)
        XCTAssertEqual(state["modelPendingTransitions"] as? Int, 1)
        XCTAssertGreaterThan(state["heldWrites"] as? Int ?? 0, 0)
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("afventer bekræftelse"))
        XCTAssertFalse(app.buttons["favorites.retry"].exists)
        assertMembership(state)
    }

    func testSustainedPendingSurvivesMetadataRevisionsAndHiddenResolveDoesNotResurrect() throws {
        tap("sustained")
        try assertSustainedDelay()
        tap("resolve"); waitForResolved()
        try assertNoResurrection("resolved visible pending does not reappear")

        // Deliver real metadata after a one-second local transport latency.
        // The actual title pages away before delivery; no product visibility or
        // timer state is changed by the fixture.
        tap("sustained")
        try tapPage(1)
        wait("actual shared messages page") { self.app.buttons["minside.page.messages"].value as? String == "Valgt" }
        wait("real pending metadata delivered while saved page is hidden") {
            guard let state = try? self.notice() else { return false }
            return state["modelState"] as? String == "pending" && state["pageVisible"] as? Bool == false
                && (state["metadataUpdates"] as? Int ?? 0) >= 10
        }
        capture("actual hidden saved-page lifecycle and pending model")
        tap("resolve"); waitForResolved()
        try tapPage(0)
        wait("saved page actually returns") { self.app.buttons["minside.page.saved"].value as? String == "Valgt" }
        try assertNoResurrection("resolved while hidden remains absent after reentry and 850 ms")
        let returned = try notice()
        let pageEvents = try XCTUnwrap(returned["pageEvents"] as? [[String: Any]])
        XCTAssertTrue(pageEvents.contains { $0["visible"] as? Bool == false })
        XCTAssertEqual(pageEvents.last?["visible"] as? Bool, true)

        tap("sustained")
        try assertSustainedDelay()
        tap("resolve"); waitForResolved()
        try assertNoResurrection("new visible pending has its own delay and cancels after resolution")
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }

    func testPhysicalWriteFailureDuringDelayIsImmediateAndRetryWaitsForRealCompletion() throws {
        tap("failure")
        wait("actual local write failure") {
            guard let state = try? self.notice() else { return false }
            return state["phase"] as? String == "write-failed" && state["modelState"] as? String == "writeFailed"
                && state["noticeVisible"] as? Bool == true
        }
        let failed = try notice()
        capture("actual writeFailed interrupts the pending presentation delay")
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("kunne ikke gemmes på denne enhed"))
        XCTAssertEqual(failed["canRetry"] as? Bool, true)
        let events = try XCTUnwrap(failed["visibilityEvents"] as? [[String: Any]])
        let appearances = events.filter { $0["visible"] as? Bool == true }
        XCTAssertEqual(appearances.count, 1)
        let errorAppearance = try XCTUnwrap(appearances.first)
        XCTAssertEqual(errorAppearance["state"] as? String, "writeFailed")
        let errorDelay = try XCTUnwrap(errorAppearance["afterFailure"] as? Double)
        XCTAssertGreaterThanOrEqual(errorDelay, 0)
        XCTAssertLessThan(errorDelay, 0.4, "Failure is not delayed by the generic 600 ms grace period")
        assertMembership(failed)
        let originalGeneration = try XCTUnwrap(failed["generation"] as? String)
        let retry = app.buttons["favorites.retry"]
        // At the largest text size the complete error card is taller than the
        // viewport. Reach its real button by scrolling the actual saved list.
        let list = app.descendants(matching: .any).matching(identifier: "notifications.fixture.favorites").firstMatch
        for _ in 0..<8 {
            if retry.exists && retry.isHittable { break }
            list.swipeUp(velocity: .slow)
        }
        capture("actual retry reached within the scrolling error card")
        XCTAssertTrue(retry.exists && retry.isHittable); retry.tap()
        wait("actual retry registered with its physical completion held") {
            guard let state = try? self.notice() else { return false }
            return state["phase"] as? String == "retry-held" && state["heldWrites"] as? Int == 1
        }
        let held = try notice()
        capture("retry preserves the failure until the real journal callback")
        XCTAssertEqual(held["modelState"] as? String, "writeFailed")
        XCTAssertEqual(held["canRetry"] as? Bool, true)
        XCTAssertEqual(held["retryGenerations"] as? [String], [originalGeneration])
        XCTAssertEqual(held["generation"] as? String, originalGeneration)
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("kunne ikke gemmes på denne enhed"))
        assertMembership(held)
        tap("resolve"); waitForResolved()
        try assertNoResurrection("successful real retry clears failure without a stale generic notice")
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }

    func testOwnerChangeDuringPendingCancelsTheOriginalGenerationReveal() throws {
        tap("owner")
        wait("real owner changed and stale-delay observation finished") {
            guard let state = try? self.notice() else { return false }
            return state["phase"] as? String == "owner-complete" && state["modelState"] as? String == "ready"
                && state["heldWrites"] as? Int == 0
        }
        let state = try notice()
        capture("old pending task and journal callbacks after actual context change")
        XCTAssertEqual(state["modelPendingTransitions"] as? Int, 1)
        XCTAssertNotEqual(state["generation"] as? String, state["originalGeneration"] as? String)
        XCTAssertEqual(state["memberIDs"] as? [String], ["saved-culture", "saved-film", "saved-music"])
        XCTAssertEqual(state["pendingIDs"] as? [String], [])
        XCTAssertEqual(state["membershipTicketsCurrent"] as? Bool, false, "The original owner's tickets cannot become the guest's tickets")
        XCTAssertEqual(state["noticeAppearances"] as? Int, 0)
        XCTAssertEqual(state["noticeVisible"] as? Bool, false)
        XCTAssertEqual(state["retryGenerations"] as? [String], [])
        XCTAssertFalse(app.staticTexts["favorites.issue"].exists)
        observeRealTime(0.85)
        capture("old-generation notice remains absent after a further 850 ms")
        XCTAssertEqual(try notice()["noticeAppearances"] as? Int, 0)
        XCTAssertEqual(try root()["firebaseStarted"] as? Bool, false)
    }
}
