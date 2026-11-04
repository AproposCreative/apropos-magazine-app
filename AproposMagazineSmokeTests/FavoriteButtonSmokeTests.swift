import XCTest

final class FavoriteButtonSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var usesAccessibilityText = false
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposFavoriteButtonSmoke", "-FavoriteButtonScenario", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["favorite.fixture.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["favorite.fixture.firebase"].label, "Firebase: ikke startet")
        wait(app.staticTexts["favorite.fixture.ready"], key: "label", equals: "Klar")
        usesAccessibilityText = app.staticTexts["favorite.fixture.textSize"].label == "Tilgængelighedstekst"
    }
    private var control: XCUIElement { app.buttons["favorite.control"] }
    private func wait(_ element: XCUIElement, key: String, equals value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "%K == %@", key, value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }
    private func selected(_ isSelected: Bool) {
        let prefix = isSelected ? "Valgt" : "Ikke valgt"
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", prefix), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }
    private func exists(_ element: XCUIElement, _ value: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: value)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func showPanel() {
        control.tap()
        XCTAssertTrue(app.buttons["favorite.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["favorites.issue"].exists)
        XCTAssertTrue(app.staticTexts["Gemte artikler"].exists)
        if usesAccessibilityText {
            XCTAssertLessThan(app.buttons["favorite.close"].frame.minY, app.frame.height * 0.25,
                              "Large text must open in a tall panel, without first expanding a half-height sheet")
        }
    }
    private func tapVisible(_ button: XCUIElement) {
        for _ in 0..<5 {
            if button.isHittable {
                if button.identifier == "favorites.retry" { capture("Favorit — synlig retry før tryk") }
                button.tap(); return
            }
            app.swipeUp()
        }
        XCTFail("The panel action must remain reachable at this text size: \(button.identifier)")
    }

    func testNormalArticleToggleKeepsSelectionAndOriginalHeaderGeometry() {
        launch("normal"); selected(false)
        // Preserve the existing 32pt header control beside Share. Expanding its
        // target is a separate header-layout change, not part of this feedback fix.
        XCTAssertEqual(control.frame.width, 32, accuracy: 1)
        XCTAssertEqual(control.frame.height, 32, accuracy: 1)
        control.tap(); selected(true)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: ready")
        XCTAssertFalse(app.buttons["favorite.close"].exists)
        capture("Favorit — normal valgt artikel")
        control.tap(); selected(false)
    }

    func testPendingGuestChoiceShowsCollectionNoticeAndCanBeReversed() {
        launch("pending"); control.tap(); selected(true)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: pending")
        showPanel()
        XCTAssertFalse(app.buttons["favorites.retry"].exists)
        XCTAssertEqual(app.staticTexts["favorite.selectionStatus"].label, "Denne artikel er valgt i din samling.")
        capture("Favorit — afventende lokal gemning og samlingsstatus")
        tapVisible(app.buttons["favorite.selection"])
        wait(app.staticTexts["favorite.selectionStatus"], key: "label", equals: "Denne artikel er ikke valgt i din samling.")
        XCTAssertEqual(app.buttons["favorite.selection"].label, "Gem artikel")
        // The selection action is distinct from retrying the storage operation.
        if app.buttons["favorite.close"].exists { tapVisible(app.buttons["favorite.close"]) }
        selected(false)
        app.buttons["favorite.fixture.release"].tap()
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: ready")
        selected(false)
    }

    func testLocalWriteFailureCanBeRetriedWithoutReversingTheChoice() {
        launch("localFailure"); control.tap(); selected(true)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: writeFailed")
        showPanel()
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("denne enhed"))
        capture("Favorit — lokal fejl med tydelig prøve igen")
        tapVisible(app.buttons["favorites.retry"])
        exists(app.staticTexts["favorites.issue"], false)
        if app.buttons["favorite.close"].exists { tapVisible(app.buttons["favorite.close"]) }
        selected(true)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: ready")
    }

    func testReadFailureKeepsChoiceUnknownUntilRetryLoadsAndEnablesSamePanel() {
        launch("readFailure")
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: readFailed")
        let unknown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "Valg endnu ukendt"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [unknown], timeout: 8), .completed)
        showPanel()
        XCTAssertEqual(app.staticTexts["favorite.selectionStatus"].label, "Artiklens valg kan ikke vises, før dine gemte artikler er indlæst.")
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("kunne ikke indlæses"))
        let selection = app.buttons["favorite.selection"]
        XCTAssertTrue(selection.exists); XCTAssertEqual(selection.label, "Gem artikel")
        XCTAssertFalse(selection.isEnabled, "Unknown membership must not offer an actionable save")
        capture("Favorit — ukendt valg ved læsefejl")
        tapVisible(app.buttons["favorites.retry"])
        exists(app.staticTexts["favorites.issue"], false)
        XCTAssertTrue(app.buttons["favorite.close"].exists, "Successful read keeps this same panel open")
        wait(app.staticTexts["favorite.selectionStatus"], key: "label", equals: "Denne artikel er ikke valgt i din samling.")
        XCTAssertTrue(selection.isEnabled)
        capture("Favorit — genindlæst samling giver kendt valg")
        tapVisible(selection)
        wait(app.staticTexts["favorite.selectionStatus"], key: "label", equals: "Denne artikel er valgt i din samling.")
        XCTAssertEqual(selection.label, "Fjern fra gemte artikler")
        tapVisible(app.buttons["favorite.close"])
        selected(true)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: ready")
    }

    func testFailedAccountRemovalStaysUnselectedAndRetryConfirmsRemoval() {
        launch("removal"); selected(false)
        showPanel()
        XCTAssertTrue(app.staticTexts["favorites.issue"].label.contains("synkroniseret"))
        XCTAssertEqual(app.staticTexts["favorite.selectionStatus"].label, "Denne artikel er ikke valgt i din samling.")
        capture("Favorit — fjernelse afventer bekræftelse")
        tapVisible(app.buttons["favorites.retry"])
        exists(app.staticTexts["favorites.issue"], false)
        if app.buttons["favorite.close"].exists { tapVisible(app.buttons["favorite.close"]) }
        selected(false)
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: ready")
    }

    func testRetryAccountRoundTripDismissesOldPanelAndRejectsLateReceipt() {
        launch("retryABA"); selected(false); showPanel()
        tapVisible(app.buttons["favorites.retry"])
        exists(app.buttons["favorite.close"], false)
        wait(app.staticTexts["favorite.fixture.oldCompletion"], key: "label", equals: "Gammel kvittering afvist")
        wait(app.staticTexts["favorite.fixture.state"], key: "label", equals: "Lagring: pending")
        selected(false)
        capture("Favorit — kontoskift afviser gammel kvittering")
        showPanel()
        XCTAssertFalse(app.buttons["favorites.retry"].exists, "The new account generation owns its own pending choice")
    }
}
