import XCTest

/// Native UI over the actual shared form/Auth/reauth/coordinator composition.
/// The injected held user, SDK result and HTTP response never contact services.
final class EmailReauthenticationSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ scenario: String, resuming: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposEmailReauthenticationSmoke", "-EmailReauthenticationScenario", scenario]
        if resuming { app.launchArguments.append("-AproposDeletionResume") }
        app.launch()
        XCTAssertTrue(app.staticTexts["emailReauth.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["emailReauth.firebase"].label, "Firebase: ikke startet")
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        if resuming {
            wait("Cold actual startup loads the original checkpoint without reader publication") { $0["restartReady"] as? Bool == true }
            assertRestartBoundary()
            XCTAssertEqual(report()["sdkCalls"] as? Int, 0)
            XCTAssertEqual(report()["httpCalls"] as? Int, 0)
            XCTAssertEqual(report()["hasParentReceipt"] as? Bool, false)
            XCTAssertEqual(report()["canBeginLedger"] as? Bool, false)
        }
    }
    private func assertRestartBoundary() {
        let state = report()
        XCTAssertEqual(state["resuming"] as? Bool, true)
        XCTAssertEqual(state["readerUnresolved"] as? Bool, true)
        XCTAssertEqual(state["bootstrapUID"] as? String, "local-reader-A")
        XCTAssertEqual(state["originalContextCurrent"] as? Bool, true)
        XCTAssertEqual(state["checkpointPhase"] as? String, "ledger", "Historical ledger intent cannot skip fresh parent reconciliation")
        for counter in ["epochReads", "drainFactories", "readerEffects", "readerPublications"] {
            XCTAssertEqual(state[counter] as? Int, 0, counter)
        }
        XCTAssertEqual(state["firebaseStarted"] as? Bool, false)
    }
    private func assertOriginalParentRequest() {
        let body = report()["originalParentBody"] as? String
        XCTAssertNotNil(body); XCTAssertFalse(body?.isEmpty ?? true)
        XCTAssertEqual(report()["sentBodies"] as? [String], body.map { [$0] })
        assertRestartBoundary()
    }
    private func report() -> [String: Any] {
        let candidates = app.staticTexts.matching(identifier: "emailReauth.report").allElementsBoundByIndex
        let visible = candidates.first(where: \.isHittable) ?? candidates.first
        guard let value = visible?.value as? String, let data = value.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    private func wait(_ description: String, _ predicate: @escaping ([String: Any]) -> Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }; return predicate(self.report())
        }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 8)
        if result != .completed {
            let state = XCTAttachment(string: String(describing: report()) + "\n" + app.debugDescription)
            state.name = description + " — failed observation"; state.lifetime = .keepAlways; add(state)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = description + " — failed observation"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        XCTAssertEqual(result, .completed, description)
    }
    private func exposedFormBottom() -> CGFloat {
        let panel = app.otherElements["emailReauth.fixtureControls"]
        XCTAssertTrue(panel.exists, "Fixture controls must occupy a separate measured region")
        var bottom = min(app.frame.maxY - 32, panel.frame.minY)
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
        return bottom
    }
    private func scrollFormUp() {
        let form = app.collectionViews["reauth.form"]
        guard form.exists else { app.swipeUp(); return }
        let top = max(form.frame.minY, app.buttons["reauth.cancel"].frame.maxY) + 12
        let bottom = min(form.frame.maxY, exposedFormBottom())
        XCTAssertGreaterThan(bottom - top, 60, "The gesture must remain in the exposed production form")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = form.frame.maxX - 24
        origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.85))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: top + (bottom - top) * 0.15)))
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        _ = button.waitForExistence(timeout: 2)
        func fullyExposed() -> Bool {
            guard button.exists, button.isHittable else { return false }
            guard id == "account.submit" else { return true }
            let bottom = exposedFormBottom()
            return button.frame.minY >= app.buttons["reauth.cancel"].frame.maxY + 12 && button.frame.maxY <= bottom
        }
        for _ in 0..<6 { if fullyExposed() { break }; scrollFormUp() }
        if !fullyExposed() {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Unreachable control — " + id; image.lifetime = .keepAlways; add(image)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Unreachable control tree — " + id; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(button.exists, id)
        XCTAssertTrue(fullyExposed(), "The full confirmation button must be exposed above keyboard and fixture controls")
        XCTAssertTrue(button.isHittable, id)
        if id == "account.submit" { capture("Full confirmation button before tap", required: [button, app.buttons["reauth.cancel"]]) }
        button.tap()
    }
    private func enterPassword(_ value: String) {
        let field = app.secureTextFields["account.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<6 { if field.isHittable { break }; scrollFormUp() }
        XCTAssertTrue(field.isHittable); field.tap(); field.typeText(value)
    }
    private func start() {
        tap("emailReauth.begin")
        wait("Original held-user prompt is waiting") {
            $0["promptState"] as? String == "waitingPassword"
                && ($0["actionIDs"] as? [String])?.last == $0["activeID"] as? String
        }
        XCTAssertTrue(app.buttons["reauth.cancel"].waitForExistence(timeout: 5))
    }
    private func assertLockedPurpose() {
        XCTAssertEqual(app.staticTexts["account.lockedEmail"].label, "original.reader@example.invalid")
        XCTAssertFalse(app.textFields["account.email"].exists)
        XCTAssertFalse(app.staticTexts["canonical@example.invalid"].exists)
        XCTAssertFalse(app.secureTextFields["account.confirmation"].exists)
        XCTAssertEqual(app.buttons["account.submit"].label, "Bekræft identitet")
        for label in ["Log ind", "Opret konto", "Ny her? Opret med e-mail", "Har du en konto? Log ind",
                      "Glemt adgangskode?", "Send nulstillingsmail", "Tilbage til login"] {
            XCTAssertFalse(app.buttons[label].exists, label)
        }
        XCTAssertEqual(app.switches.count, 0, "No newsletter choice belongs in reauthentication")
    }
    private func assertEmptyPassword() {
        let value = app.secureTextFields["account.password"].value as? String
        XCTAssertTrue(value == nil || value == "" || value == "Adgangskode", "A new challenge cannot replay a password")
    }
    private func capture(_ name: String, required: [XCUIElement]) {
        for element in required {
            XCTAssertTrue(element.exists)
            XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY)
        }
        let evidence = XCTAttachment(string: String(describing: report()))
        evidence.name = name + " — actual composition counters/system text"; evidence.lifetime = .keepAlways; add(evidence)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testLockedHeldUserEmailUsesSharedFormAndCancelClearsUnsubmittedPassword() {
        launch("normal"); start(); assertLockedPurpose(); assertEmptyPassword()
        capture("Reauthentication — locked original SDK email and shared password field",
                required: [app.staticTexts["account.lockedEmail"], app.secureTextFields["account.password"], app.buttons["reauth.cancel"]])
        enterPassword("Unsubmitted123!")
        wait("Draft contains entered password") { $0["passwordsCleared"] as? Bool == false }
        tap("reauth.cancel")
        wait("Cancellation clears the original draft without an SDK exchange") {
            $0["promptState"] as? String == "closed" && $0["passwordsCleared"] as? Bool == true && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 0); XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        start(); assertEmptyPassword(); assertLockedPurpose(); tap("reauth.cancel")
    }

    func testWrongPasswordKeepsNeutralFeedbackThenExplicitRetryUsesFreshActionAndClearedForm() {
        runWrongPassword(resuming: false)
    }

    func testRestartEmailWrongPasswordRequiresFreshActionAndOriginalParentReconciliation() {
        runWrongPassword(resuming: true)
    }

    private func runWrongPassword(resuming: Bool) {
        launch("wrongPassword", resuming: resuming); start(); let firstID = report()["activeID"] as? String
        if resuming {
            assertRestartBoundary()
            XCTAssertEqual(report()["canBeginLedger"] as? Bool, false)
        }
        enterPassword("Wrong123!"); tap("account.submit")
        wait("Actual local SDK failure remains on the original prompt") { $0["promptState"] as? String == "failed" }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 1); XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        XCTAssertEqual(report()["passwordsCleared"] as? Bool, true)
        let error = app.staticTexts["account.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5)); XCTAssertFalse(error.label.contains("PRIVATE"))
        XCTAssertFalse(error.label.localizedCaseInsensitiveContains("log ind"))
        let retry = app.buttons["reauth.retry"]
        for _ in 0..<5 { if retry.isHittable && error.isHittable { break }; scrollFormUp() }
        XCTAssertTrue(app.buttons["account.submit"].exists)
        XCTAssertFalse(app.buttons["account.submit"].isEnabled)
        capture("Wrong password — neutral visible feedback and explicit fresh retry", required: [error, retry, app.buttons["reauth.cancel"]])
        tap("reauth.retry")
        wait("Retry creates a new original challenge") {
            $0["promptState"] as? String == "waitingPassword" && $0["activeID"] as? String != firstID
                && ($0["actionIDs"] as? [String])?.count == 2
        }
        assertLockedPurpose(); assertEmptyPassword()
        XCTAssertEqual((report()["actionIDs"] as? [String])?.count, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 1)
        enterPassword("Correct123!"); tap("account.submit")
        wait("Actual composition accepts only the second local reauthentication") {
            $0["promptState"] as? String == "closed" && $0["status"] as? String == "scopedCloudDataRemoved"
                && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2); XCTAssertEqual(report()["httpCalls"] as? Int, 1)
        XCTAssertEqual(report()["passwordsCleared"] as? Bool, true)
        XCTAssertEqual(report()["credentialEmails"] as? [String], ["original.reader@example.invalid", "original.reader@example.invalid"])
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        if resuming {
            assertOriginalParentRequest()
            XCTAssertEqual(report()["hasParentReceipt"] as? Bool, true)
            XCTAssertEqual(report()["canBeginLedger"] as? Bool, true, "Only the fresh parent response enables a later explicit ledger action")
            XCTAssertEqual(report()["httpCalls"] as? Int, 1, "No automatic ledger request")
        }
    }

    func testCancelRemainsAvailableDuringHeldSDKAndPhysicalSlotBlocksImmediateRestart() {
        launch("held"); start(); enterPassword("Correct123!"); tap("account.submit")
        wait("Physical reauthentication is deliberately held") { $0["sdkHeld"] as? Bool == true }
        XCTAssertFalse(app.buttons["account.submit"].isEnabled); XCTAssertTrue(app.buttons["reauth.cancel"].isEnabled)
        capture("Held SDK — cancel remains available", required: [app.buttons["reauth.cancel"]])
        tap("reauth.cancel")
        wait("Prompt closes while original physical work remains reserved") {
            $0["promptState"] as? String == "closed" && $0["physicalFlight"] as? Bool == true && $0["passwordsCleared"] as? Bool == true
        }
        tap("emailReauth.begin")
        wait("A second action cannot bypass held physical work") { $0["rejectedStarts"] as? Int == 1 }
        XCTAssertEqual((report()["actionIDs"] as? [String])?.count, 1); XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        tap("emailReauth.release")
        wait("Old cancelled SDK result physically returned") { $0["physicalFlight"] as? Bool == false }
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        start(); assertEmptyPassword(); tap("reauth.cancel")
    }

    func testAccountRoundTripDismissesOriginalPromptAndOldCompletionCannotCloseNewChallenge() {
        launch("held"); start(); let originalID = report()["activeID"] as? String
        enterPassword("Correct123!"); tap("account.submit")
        wait("Original A is held at the actual SDK adapter") { $0["sdkHeld"] as? Bool == true }
        tap("emailReauth.roundTrip")
        wait("Account generation change clears the original prompt") {
            $0["promptState"] as? String == "closed" && $0["passwordsCleared"] as? Bool == true && $0["physicalFlight"] as? Bool == true
        }
        tap("emailReauth.release")
        wait("Stale SDK response has returned without HTTP") { $0["physicalFlight"] as? Bool == false }
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        start(); let newID = report()["activeID"] as? String
        XCTAssertNotEqual(originalID, newID); assertEmptyPassword()
        tap("emailReauth.oldPrompt")
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return self.report()["activeID"] as? String != newID
                || self.report()["promptState"] as? String != "waitingPassword"
        }, object: nil)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 1), .completed,
                       "Observe beyond asynchronous sheet publication; old completion cannot dismiss new A")
        XCTAssertEqual(report()["activeID"] as? String, newID)
        XCTAssertTrue(app.buttons["reauth.cancel"].exists)
        capture("New A challenge survives old prompt completion", required: [app.staticTexts["account.lockedEmail"], app.buttons["reauth.cancel"]])
        enterPassword("Correct123!"); tap("account.submit")
        wait("Only new A proceeds to the local endpoint") { $0["status"] as? String == "scopedCloudDataRemoved" && $0["promptState"] as? String == "closed" }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2); XCTAssertEqual(report()["httpCalls"] as? Int, 1)
        XCTAssertEqual(report()["passwordsCleared"] as? Bool, true); XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }
}
