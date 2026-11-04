import XCTest

/// Native UI smoke over the production email form, using local fixture operations.
final class AccountSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Firebase: ikke startet"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app.terminate(); app = nil }

    private func tap(_ title: String) {
        let button = app.buttons[title]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func enter(_ id: String, _ text: String, secure: Bool = false) {
        let field = secure ? app.secureTextFields[id] : app.textFields[id]
        if !field.isHittable { app.swipeUp() }
        field.tap()
        field.typeText(text)
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testInvalidEmailStaysLocalAndModeSwitchClearsError() {
        tap("Log ind")
        XCTAssertTrue(app.staticTexts["Skriv en gyldig e-mailadresse."].exists)
        XCTAssertTrue(app.staticTexts["Testkald: 0 · Ingen testkald"].exists)
        capture("Ugyldig e-mail — nul transportkald")
        tap("Glemt adgangskode?")
        XCTAssertFalse(app.staticTexts["Skriv en gyldig e-mailadresse."].exists)
        XCTAssertFalse(app.secureTextFields["account.password"].exists)
        XCTAssertTrue(app.buttons["Send nulstillingsmail"].exists)
        tap("Tilbage til login")
        XCTAssertTrue(app.secureTextFields["account.password"].exists)
    }

    func testSignupMismatchThenSuccessfulFixtureClearsPasswords() {
        tap("Ny her? Opret med e-mail")
        enter("account.email", "reader@example.invalid")
        enter("account.password", "Example123!", secure: true)
        enter("account.confirmation", "Mismatch123!", secure: true)
        app.swipeUp()
        tap("Opret konto")
        XCTAssertTrue(app.staticTexts["Adgangskoderne er ikke ens."].exists)
        capture("Adgangskoder matcher ikke")
        let confirmation = app.secureTextFields["account.confirmation"]
        confirmation.tap()
        confirmation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Mismatch123!".count) + "Example123!")
        app.swipeUp()
        tap("Opret konto")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Adgangskoder er ryddet"].waitForExistence(timeout: 5))
        capture("Lokal oprettelse — adgangskoder ryddet")
    }

    func testOfflineFailureCanRetryWithoutRealMail() {
        let failureSwitch = app.switches["Næste testkald fejler"]
        failureSwitch.switches.firstMatch.tap()
        XCTAssertEqual(failureSwitch.value as? String, "1")
        tap("Glemt adgangskode?")
        enter("account.email", "reader@example.invalid")
        app.swipeUp()
        tap("Send nulstillingsmail")
        XCTAssertTrue(app.staticTexts["Ingen forbindelse. Prøv igen, når du er online."].waitForExistence(timeout: 5))
        capture("Netværksfejl fra lokal fixture")
        tap("Send nulstillingsmail")
        XCTAssertTrue(app.staticTexts["Hvis adressen har en konto, modtager du en mail med hjælp til at vælge en ny adgangskode."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ingen forbindelse. Prøv igen, når du er online."].exists)
        capture("Retry — neutral nulstillingsbesked")
    }

    func testLoginUsesFixtureAndClearsPassword() {
        enter("account.email", "reader@example.invalid")
        enter("account.password", "Example123!", secure: true)
        app.swipeUp()
        tap("Log ind")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Adgangskoder er ryddet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reader@example.invalid"].exists)
        capture("Lokal loginfixture — adgangskode ryddet")
    }
}
