import CoreGraphics
import XCTest

/// Actual profile state/coordinator and the same account row used by Settings.
final class ProfileSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private var lastSettingsRank = 0
    private enum Row: Int, CaseIterable {
        case intro, firebase, name, email, status, phase, pending, accountA, accountB, guest, retry, retire, newest, oldest, fail
        var id: String {
            switch self {
            case .intro: return "profile.fixture.intro"
            case .firebase: return "profile.fixture.firebase"
            case .name: return "profile.summary.name"
            case .email: return "profile.summary.email"
            case .status: return "profile.summary.status"
            case .phase: return "profile.fixture.phase"
            case .pending: return "profile.fixture.pending"
            case .accountA: return "profile.fixture.accountA"
            case .accountB: return "profile.fixture.accountB"
            case .guest: return "profile.fixture.guest"
            case .retry: return "profile.fixture.retry"
            case .retire: return "profile.fixture.retire"
            case .newest: return "profile.fixture.newest"
            case .oldest: return "profile.fixture.oldest"
            case .fail: return "profile.fixture.fail"
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false;lastRank = 0
        app = XCUIApplication();app.launchArguments = ["-AproposSmokeTesting", "-AproposProfileSmoke"];app.launch()
        XCTAssertTrue(app.scrollViews["profile.fixture.form"].waitForExistence(timeout: 10))
        assertLabel(.firebase, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate();app = nil }
    private func element(_ row: Row) -> XCUIElement {
        switch row {
        case .accountA, .accountB, .guest, .retry, .retire, .newest, .oldest, .fail: return app.buttons[row.id]
        default: return app.staticTexts[row.id]
        }
    }
    private var viewport: CGRect {
        let scroller = app.scrollViews["profile.fixture.form"].frame.intersection(app.frame)
        let navigationBar = app.navigationBars.firstMatch
        let navigationBottom = navigationBar.exists ? navigationBar.frame.maxY : app.frame.minY + 110
        let top = max(scroller.minY, navigationBottom) + 8
        let bottom = min(scroller.maxY, app.frame.maxY - 36) - 8
        return CGRect(x: scroller.minX + 12, y: top, width: max(1, scroller.width - 24), height: max(1, bottom - top))
    }
    private func scroll(up: Bool) {
        let frame = viewport
        // Small drags avoid jumping over a short status row at maximum text.
        // Replies share this scroll geometry and the same strict reveal check.
        let distance = min(240, max(80, frame.height * 0.35))
        let startY = up ? frame.midY + distance / 2 : frame.midY - distance / 2
        let endY = up ? frame.midY - distance / 2 : frame.midY + distance / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: startY))
        let end = origin.withOffset(CGVector(dx: frame.midX, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    private func anchor() -> Int {
        let candidates = Row.allCases.compactMap { row -> (CGFloat, Int)? in
            let item = element(row)
            guard item.exists, !item.frame.isEmpty else { return nil }
            let visible = item.frame.intersection(viewport)
            guard !visible.isNull, visible.height > 0 else { return nil }
            return (abs(visible.midY - viewport.midY), row.rawValue)
        }
        return candidates.min(by: { $0.0 < $1.0 })?.1 ?? lastRank
    }
    @discardableResult
    private func reveal(_ row: Row, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let item = element(row)
        for _ in 0..<28 {
            if item.exists, !item.frame.isEmpty, item.frame.midY.isFinite {
                if item.isHittable && viewport.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) {
                    lastRank = row.rawValue;return item
                }
                scroll(up: item.frame.midY >= viewport.minY)
            } else { scroll(up: row.rawValue >= anchor()) }
        }
        XCTFail("Profile row outside visible viewport: \(row.id)", file: file, line: line);return item
    }
    private func assertLabel(_ row: Row, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(row, file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element(row))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed, file: file, line: line)
    }
    private func reply(_ row: Row, file: StaticString = #filePath, line: UInt = #line) {
        let button = reveal(row, file: file, line: line)
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 4), .completed, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        XCTAssertTrue(viewport.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)), file: file, line: line)
        button.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot());attachment.name = name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private var settingsList: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "profile.fixture.settingsList").firstMatch
    }
    private func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["profile.fixture.settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap(); lastSettingsRank = 0
        XCTAssertTrue(settingsList.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.navigationBars["Indstillinger"].exists, file: file, line: line)
    }
    @discardableResult
    private func revealSettings(_ identifier: String, button: Bool = false,
                                file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let ranks = ["settings.signIn": 0, "profile.summary.name": 0, "profile.summary.email": 1,
                     "profile.summary.status": 2, "settings.retryProfile": 3, "profile.settings.loginCount": 4,
                     "profile.settings.phase": 5, "profile.settings.pending": 6, "profile.settings.firebase": 7,
                     "profile.settings.newest": 8, "settings.appVersion": 9]
        let rank = ranks[identifier] ?? 0
        let item = settingsList.descendants(matching: button ? .button : .staticText).matching(identifier: identifier).firstMatch
        for _ in 0..<28 {
            let bounds = settingsList.frame.intersection(app.frame)
            let top = max(bounds.minY, app.navigationBars["Indstillinger"].frame.maxY) + 8
            let bottom = min(bounds.maxY, app.frame.maxY - 36) - 8
            let visible = CGRect(x: bounds.minX + 12, y: top, width: max(1, bounds.width - 24), height: max(1, bottom - top))
            if item.exists, !item.frame.isEmpty, item.isHittable,
               visible.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) {
                lastSettingsRank = rank; return item
            }
            let up = item.exists && !item.frame.isEmpty ? item.frame.midY >= visible.minY : rank >= lastSettingsRank
            let distance = min(220, max(80, visible.height * 0.35))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (up ? distance / 2 : -distance / 2)))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (up ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Settings control outside viewport: \(identifier)", file: file, line: line); return item
    }
    private func assertSettingsLabel(_ identifier: String, _ label: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let item = revealSettings(identifier, file: file, line: line)
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 4), .completed, file: file, line: line)
    }
    func testNewAccountProfileAppearsBeforeOldAnswerAndLateOldAnswerCannotReplaceIt() {
        assertLabel(.name, "Kontrollerer din konto")
        reveal(.accountA).tap();assertLabel(.pending, "Ventende svar: A");reply(.newest)
        assertLabel(.name, "Læser A");assertLabel(.email, "a@example.test")
        reveal(.retry).tap();assertLabel(.pending, "Ventende svar: A")
        reveal(.accountB).tap();assertLabel(.pending, "Ventende svar: A, B")
        assertLabel(.name, "Din konto");XCTAssertFalse(element(.email).exists)
        assertLabel(.phase, "Profil: hentes")
        reply(.newest);assertLabel(.name, "Læser B");assertLabel(.email, "b@example.test")
        assertLabel(.pending, "Ventende svar: A");assertLabel(.phase, "Profil: klar")
        reveal(.name);capture("Profil — B er klar mens gammelt A-svar stadig venter")
        reply(.oldest);assertLabel(.pending, "Ventende svar: ingen")
        assertLabel(.name, "Læser B");assertLabel(.email, "b@example.test")
        reveal(.guest).tap();assertLabel(.phase, "Profil: gæst")
        assertLabel(.name, "Log ind eller opret en bruger");XCTAssertFalse(element(.email).exists)
        capture("Profil — gæst viser ingen tidligere konto")
    }
    func testReadFailureRetainsMatchingProfileWithClearScopedRetryAndReadableStatus() {
        reveal(.accountA).tap();assertLabel(.pending, "Ventende svar: A");reply(.newest)
        assertLabel(.name, "Læser A");assertLabel(.phase, "Profil: klar")
        reveal(.retry).tap();assertLabel(.pending, "Ventende svar: A");reply(.fail)
        assertLabel(.phase, "Profil: fejl");assertLabel(.name, "Læser A")
        assertLabel(.status, "Kunne ikke hente brugerprofil. Prøv igen, når du er online.")
        capture("Profil — beholdt konto med læsbar scoped læsefejl")
        reveal(.retry).tap();assertLabel(.pending, "Ventende svar: A");reply(.newest)
        assertLabel(.phase, "Profil: klar");assertLabel(.name, "Læser A");assertLabel(.email, "a@example.test")
        capture("Profil — korrekt konto efter genforsøg")
    }
    func testSettingsSignedInIdentityIsStaticAndActualVersionIsReadableAtBottom() {
        reveal(.accountA).tap(); assertLabel(.pending, "Ventende svar: A"); reply(.newest)
        assertLabel(.name, "Læser A"); openSettings()
        let name = revealSettings("profile.summary.name")
        XCTAssertEqual(name.label, "Læser A"); XCTAssertEqual(name.elementType, .staticText)
        XCTAssertFalse(settingsList.buttons["settings.signIn"].exists)
        XCTAssertFalse(settingsList.buttons["settings.retryProfile"].exists)
        let navigationCount = app.navigationBars.count, sheetCount = app.sheets.count
        name.tap()
        XCTAssertEqual(app.navigationBars.count, navigationCount); XCTAssertEqual(app.sheets.count, sheetCount)
        XCTAssertTrue(app.navigationBars["Indstillinger"].exists); XCTAssertEqual(app.alerts.count, 0)
        capture("Indstillinger — kontoidentitet uden navigation")
        assertSettingsLabel("profile.settings.loginCount", "Login åbnet lokalt: 0")
        assertSettingsLabel("profile.settings.firebase", "Firebase: ikke startet")
        let version = revealSettings("settings.appVersion")
        XCTAssertNotNil(version.label.range(of: #"^Version [0-9]+(?:\.[0-9]+)+ \([0-9]+\)$"#, options: .regularExpression))
        capture("Indstillinger — statisk konto og aktuel version nederst")
    }
    func testSettingsGuestLoginInvokesOnlyTheLocalLoginCallback() {
        reveal(.guest).tap(); assertLabel(.phase, "Profil: gæst"); openSettings()
        let login = revealSettings("settings.signIn", button: true)
        XCTAssertTrue(login.isEnabled); login.tap()
        assertSettingsLabel("profile.settings.loginCount", "Login åbnet lokalt: 1")
        XCTAssertTrue(app.navigationBars["Indstillinger"].exists)
        XCTAssertFalse(settingsList.buttons["settings.retryProfile"].exists)
        assertSettingsLabel("profile.settings.firebase", "Firebase: ikke startet")
        capture("Indstillinger — gæstelogin når den lokale callback")
    }
    func testSettingsFailedSignedInProfileHasExplicitRetryAndRecoversInPlace() {
        reveal(.accountA).tap(); assertLabel(.pending, "Ventende svar: A"); reply(.newest)
        reveal(.retry).tap(); assertLabel(.pending, "Ventende svar: A"); reply(.fail)
        assertLabel(.phase, "Profil: fejl"); openSettings()
        XCTAssertFalse(settingsList.buttons["settings.signIn"].exists)
        assertSettingsLabel("profile.summary.name", "Læser A")
        let retry = revealSettings("settings.retryProfile", button: true)
        capture("Indstillinger — profilfejl med tydeligt genforsøg")
        retry.tap()
        assertSettingsLabel("profile.settings.pending", "Ventende svar: A")
        assertSettingsLabel("profile.settings.phase", "Profil: hentes")
        revealSettings("profile.settings.newest", button: true).tap()
        assertSettingsLabel("profile.settings.phase", "Profil: klar")
        XCTAssertFalse(settingsList.buttons["settings.retryProfile"].exists)
        assertSettingsLabel("profile.settings.loginCount", "Login åbnet lokalt: 0")
        assertSettingsLabel("profile.settings.firebase", "Firebase: ikke startet")
        capture("Indstillinger — særskilt genforsøg gendanner profilen")
    }
    func testSettingsOwnedIdleProfileHasActualRetryAndWaitsForFreshReply() {
        reveal(.accountA).tap(); assertLabel(.pending, "Ventende svar: A")
        reveal(.retire).tap(); assertLabel(.phase, "Profil: venter")
        assertLabel(.status, "Profilen er endnu ikke indlæst.")
        openSettings()
        assertSettingsLabel("profile.summary.name", "Din konto")
        XCTAssertFalse(settingsList.buttons["settings.signIn"].exists)
        XCTAssertFalse(settingsList.staticTexts["profile.summary.email"].exists)
        let retry = revealSettings("settings.retryProfile", button: true)
        XCTAssertEqual(retry.label, "Prøv igen")
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        captureControlGeometry("Profilgenforsøg — faktisk label og trykflade", controls: [retry])
        capture("Indstillinger — ejet profil uden svar har eksplicit genforsøg")
        retry.tap()
        assertSettingsLabel("profile.settings.phase", "Profil: hentes")
        assertSettingsLabel("profile.settings.pending", "Ventende svar: A, A")
        XCTAssertFalse(settingsList.buttons["settings.retryProfile"].exists)
        XCTAssertFalse(settingsList.staticTexts["profile.summary.email"].exists)
        revealSettings("profile.settings.newest", button: true).tap()
        assertSettingsLabel("profile.settings.phase", "Profil: klar")
        assertSettingsLabel("profile.summary.name", "Læser A")
        assertSettingsLabel("profile.summary.email", "a@example.test")
        XCTAssertFalse(settingsList.buttons["settings.retryProfile"].exists)
        assertSettingsLabel("profile.settings.loginCount", "Login åbnet lokalt: 0")
        assertSettingsLabel("profile.settings.firebase", "Firebase: ikke startet")
        let name = revealSettings("profile.summary.name")
        let email = revealSettings("profile.summary.email")
        let visible = settingsList.frame.intersection(app.frame)
        for control in [name, email] {
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(visible.contains(CGPoint(x: control.frame.midX, y: control.frame.midY)))
        }
        captureControlGeometry("Frisk profil — identitet i viewport", controls: [name, email])
        capture("Indstillinger — faktisk nyt profilsvar afslutter genforsøg")
        let close = app.buttons["profile.settings.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable)
        close.tap()
        reply(.oldest)
        assertLabel(.name, "Læser A"); assertLabel(.phase, "Profil: klar")
    }

    private func captureControlGeometry(_ name: String, controls: [XCUIElement]) {
        let values: [[String: Any]] = controls.map {
            ["identifier": $0.identifier, "label": $0.label, "hittable": $0.isHittable,
             "frame": ["x": $0.frame.minX, "y": $0.frame.minY,
                       "width": $0.frame.width, "height": $0.frame.height]]
        }
        guard let bytes = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let json = String(data: bytes, encoding: .utf8) else {
            XCTFail("Could not capture actual control geometry"); return
        }
        let attachment = XCTAttachment(string: json)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
