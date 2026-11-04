import XCTest

final class ReaderAvailabilitySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gammel lokal artikeltekst"].exists)
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }
    private func tapVisible(_ title: String) {
        let button = app.buttons[title]
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testConfirmedWithdrawalHidesBodyAndCachedPublicStateCannotReopenIt() {
        app.buttons["Afpublicér lokalt"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen er ikke tilgængelig"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        app.buttons["Gammel cache"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen er ikke tilgængelig"].exists)
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        capture("Afpubliceret læser — gammel tekst fjernet")
        let back = app.buttons["Tilbage"]
        for _ in 0..<6 where !back.isHittable { app.swipeUp() }
        XCTAssertTrue(back.isHittable)
        capture("Afpubliceret læser — tilgængelige navigationsknapper")
        back.tap()
        XCTAssertTrue(app.staticTexts["Tilbage valgt i test"].exists)
    }
    func testRetryIgnoresOldCallbackAndRepublicationRequiresNewBody() {
        app.buttons["Afpublicér lokalt"].tap()
        app.buttons["Netværksfejl"].tap()
        XCTAssertTrue(app.staticTexts["Status kunne ikke bekræftes. Prøv igen, når du er online."].exists)
        tapVisible("Prøv igen")
        app.buttons["Gammelt svar"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen er ikke tilgængelig"].exists)
        app.buttons["Genpublicér lokalt"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen skal hentes på ny."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        tapVisible("Prøv at hente artiklen igen")
        XCTAssertTrue(app.staticTexts["Ny genpubliceret artikeltekst"].exists)
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        capture("Genpubliceret læser — kun ny revision tilladt")
    }
    func testCorrectionWithoutWithdrawalRequiresNewBodyAtSamePublicationDate() {
        app.buttons["Genpublicér lokalt"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen skal hentes på ny."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        tapVisible("Prøv at hente artiklen igen")
        XCTAssertTrue(app.staticTexts["Ny genpubliceret artikeltekst"].exists)
        XCTAssertFalse(app.staticTexts["Gammel lokal artikeltekst"].exists)
        capture("Indholdsrettelse — uændret publiceringsdato, ny tekst")
    }

}
