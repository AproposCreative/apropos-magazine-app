import XCTest

final class ArticleListenSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderSmoke", "-ReaderListenSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }

    func testLegacyAINarrationFromThePreviousCatalogCanStillBeSelectedOnline() {
        app.terminate()
        app.launchArguments.append("legacy-audio-catalog")
        app.launch()
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].waitForExistence(timeout: 10))
        let listen = app.buttons["reader.listen"]
        XCTAssertFalse(listen.exists)
        app.buttons["Indlæs lydliste"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        XCTAssertTrue(listen.isHittable)
        listen.tap()
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 1")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Oprindelig kompakt lytteknap — eksisterende AI-katalog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Gå offline"].tap()
        app.buttons["Download lyd lokalt"].tap()
        XCTAssertTrue(listen.exists, "Known audio keeps an explanation in the reader")
        XCTAssertFalse(listen.isEnabled, "Legacy streaming must not fabricate verified offline provenance")
        XCTAssertTrue(listen.label.localizedLowercase.contains("internet"))
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 1")
        let offline = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        offline.name = "Offline legacy — synlig forklaring uden afspilning"
        offline.lifetime = .keepAlways; add(offline)
        app.buttons["Gå online"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        listen.tap()
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 2")
        app.buttons["Fjern lyd"].tap()
        XCTAssertFalse(listen.exists)
        app.buttons["Indlæs lydliste"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        app.buttons["Afpublicér lokalt"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen er ikke tilgængelig"].waitForExistence(timeout: 3))
        XCTAssertFalse(listen.exists)
    }

    func testDelayedCatalogRevealsListenAndCurrentOfflineRecordingIsRequired() {
        let listen = app.buttons["reader.listen"]
        XCTAssertFalse(listen.exists)
        // Only the catalog publishes here: neither the article nor progress changes.
        app.buttons["Indlæs lydliste"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        XCTAssertTrue(listen.isHittable)
        XCTAssertGreaterThanOrEqual(listen.frame.height, 44)
        listen.tap()
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 1")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Lyt til artiklen — sen lydliste viser fælles knap"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Gå offline"].tap()
        XCTAssertTrue(listen.exists)
        XCTAssertFalse(listen.isEnabled)
        XCTAssertTrue(listen.label.localizedLowercase.contains("internet"))
        app.buttons["Download lyd lokalt"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        listen.tap()
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 2")
        app.buttons["Erstat lydfil"].tap()
        XCTAssertTrue(listen.exists)
        XCTAssertFalse(listen.isEnabled, "Another file is not the downloaded recording")
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 2")
        app.buttons["Gå online"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        app.buttons["Fjern lyd"].tap()
        XCTAssertFalse(listen.exists)
        app.buttons["Indlæs lydliste"].tap()
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        app.buttons["Afpublicér lokalt"].tap()
        XCTAssertTrue(app.staticTexts["Artiklen er ikke tilgængelig"].waitForExistence(timeout: 3))
        XCTAssertFalse(listen.exists)
        XCTAssertEqual(app.staticTexts["reader.listen.count"].label, "Lokale afspilninger: 2")
    }
}
