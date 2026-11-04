import XCTest

/// Actual native Apple button/controller lifecycle with a local injected
/// provider. These tests do not demonstrate real Apple or Firebase acceptance.
final class AppleReauthenticationSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func launch(_ scenario: String? = nil, resuming: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposAppleReauthenticationSmoke"]
        if let scenario { app.launchArguments += ["-AppleReauthenticationScenario", scenario] }
        if resuming { app.launchArguments.append("-AproposDeletionResume") }
        app.launch()
        XCTAssertTrue(app.staticTexts["appleReauth.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["appleReauth.firebase"].label, "Firebase: ikke startet")
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
        let reports = app.staticTexts.matching(identifier: "appleReauth.report").allElementsBoundByIndex
        let visible = reports.first(where: \.isHittable) ?? reports.first
        guard let value = visible?.value as? String,
              let data = value.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    private func wait(_ message: String, _ predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }; return predicate(self.report())
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        if result != .completed {
            let image = XCTAttachment(screenshot: app.screenshot()); image.name = message; image.lifetime = .keepAlways; add(image)
            let state = XCTAttachment(string: String(describing: report()) + "\n" + app.debugDescription)
            state.name = message + " — diagnostics"; state.lifetime = .keepAlways; add(state)
        }
        XCTAssertEqual(result, .completed, message)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        XCTAssertTrue(button.isEnabled, id); XCTAssertTrue(button.isHittable, id)
        XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(button.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.frame.maxY)
        button.tap()
    }
    private func capture(_ name: String, required: [XCUIElement]) {
        for element in required {
            XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(element.frame.minY, app.frame.minY)
            XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let state = XCTAttachment(string: String(describing: report()))
        state.name = name + " — local counters/system text"; state.lifetime = .keepAlways; add(state)
    }

    func testActualAppleReauthenticationButtonShowsNeutralFailureAndFreshRetry() {
        launch()
        let button = app.buttons["account.apple.reauthenticate"]
        XCTAssertEqual(button.label, "Bekræft identitet med Apple")
        XCTAssertFalse(app.buttons["account.apple.signIn"].exists)
        capture("Apple reauthentication — actual continue button", required: [button])
        tap("account.apple.reauthenticate")
        wait("One local provider request is pending") { $0["starts"] as? Int == 1 && $0["working"] as? Bool == true }
        let original = report()["challengeIDs"] as? [String]
        XCTAssertFalse(button.isEnabled)
        tap("appleReauth.failure")
        let alert = app.alerts["Kunne ikke bekræfte identitet"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let message = alert.staticTexts["Kunne ikke bekræfte din identitet med Apple. Prøv igen."]
        XCTAssertTrue(message.exists)
        XCTAssertFalse(app.alerts["Kunne ikke logge ind"].exists)
        XCTAssertFalse(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "PRIVATE")).firstMatch.exists)
        capture("Apple reauthentication — neutral provider feedback", required: [message, alert.buttons["OK"]])
        alert.buttons["OK"].tap()
        wait("Failed provider releases its physical request") { $0["working"] as? Bool == false && $0["releases"] as? Int == 1 }
        tap("account.apple.reauthenticate")
        wait("Explicit retry creates a fresh provider challenge") { $0["starts"] as? Int == 2 && $0["working"] as? Bool == true }
        let challenges = report()["challengeIDs"] as? [String]
        XCTAssertEqual(challenges?.first, original?.first); XCTAssertEqual(challenges?.count, 2)
        XCTAssertNotEqual(challenges?.first, challenges?.last)
        tap("appleReauth.success")
        wait("Only the second provider result reaches the local exchange") {
            $0["working"] as? Bool == false && $0["exchanges"] as? Int == 1 && $0["releases"] as? Int == 2
        }
        XCTAssertEqual(report()["hasSession"] as? Bool, false); XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }

    func testActualButtonDetachCancelsWithValidLifetimeAndRetainsSlotUntilCallback() {
        launch(); tap("account.apple.reauthenticate")
        wait("Original local request is held") { $0["starts"] as? Int == 1 && $0["working"] as? Bool == true }
        tap("appleReauth.toggle")
        wait("Dismantle cancels without treating UI removal as a provider callback") {
            $0["cancellations"] as? Int == 1 && $0["working"] as? Bool == true && $0["releases"] as? Int == 0
        }
        XCTAssertEqual(report()["lifetimeInvalidated"] as? Bool, false)
        XCTAssertFalse(app.buttons["account.apple.reauthenticate"].exists)
        capture("Apple reauthentication — detached original provider remains held",
                required: [app.staticTexts["appleReauth.detached"], app.buttons["appleReauth.success"]])
        tap("appleReauth.toggle")
        let replacement = app.buttons["account.apple.reauthenticate"]
        XCTAssertTrue(replacement.waitForExistence(timeout: 5)); XCTAssertFalse(replacement.isEnabled)
        XCTAssertEqual(report()["starts"] as? Int, 1)
        tap("appleReauth.success")
        wait("Original cancelled provider callback drains without exchange") {
            $0["working"] as? Bool == false && $0["releases"] as? Int == 1 && $0["exchanges"] as? Int == 0
        }
        tap("account.apple.reauthenticate")
        wait("New actual button starts only after the original physical callback") { $0["starts"] as? Int == 2 }
        tap("appleReauth.success")
        wait("New local request completes independently") {
            $0["working"] as? Bool == false && $0["releases"] as? Int == 2 && $0["exchanges"] as? Int == 1
        }
        XCTAssertEqual(report()["hasSession"] as? Bool, false); XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        capture("Apple reauthentication — new button is ready after original drain", required: [replacement])
    }

    func testActualPromptSheetWaitsForHeldSDKAndSuccessDismissalPreservesHTTP() {
        launch("composed")
        let begin = app.buttons["appleReauth.begin"]
        capture("Actual Apple composition — visible explicit entry", required: [begin])
        tap("appleReauth.begin")
        wait("Actual Auth composition publishes one original Apple prompt") {
            ($0["promptID"] as? String)?.isEmpty == false && $0["physicalFlight"] as? Bool == true
        }
        XCTAssertEqual(report()["starts"] as? Int, 0, "Presenting the sheet must not start Apple automatically")
        let originalID = report()["promptID"] as? String
        let button = app.buttons["account.apple.reauthenticate"]
        let cancel = app.buttons["reauth.apple.cancel"]
        capture("Actual Apple prompt — explicit confirmation and cancellation", required: [button, cancel])
        tap("account.apple.reauthenticate")
        wait("Actual sheet starts only one local provider") { $0["starts"] as? Int == 1 && $0["working"] as? Bool == true }
        tap("appleReauth.success")
        wait("Actual held-user SDK reauthentication remains physically pending") {
            $0["sdkHeld"] as? Bool == true && $0["sdkCalls"] as? Int == 1
        }
        XCTAssertEqual(report()["promptID"] as? String, originalID)
        XCTAssertEqual(report()["httpCalls"] as? Int, 0); XCTAssertFalse(button.isEnabled)
        XCTAssertTrue(cancel.isEnabled)
        capture("Actual Apple prompt — held SDK keeps confirmation disabled and cancel available", required: [button, cancel])
        tap("appleReauth.releaseSDK")
        wait("Successful SDK return closes only its own prompt while actual HTTP remains held") {
            $0["promptID"] as? String == "" && $0["httpHeld"] as? Bool == true
                && $0["httpCalls"] as? Int == 1 && $0["physicalFlight"] as? Bool == true
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["account.apple.reauthenticate"].exists)
        XCTAssertEqual(report()["uid"] as? String, "local-reader-A")
        XCTAssertEqual(report()["hasNewSession"] as? Bool, false)
        XCTAssertEqual(report()["cancellations"] as? Int, 0)
        capture("Actual Apple composition — successful sheet dismissal keeps original HTTP held",
                required: [app.staticTexts["appleReauth.report"], app.buttons["appleReauth.releaseHTTP"]])
        tap("appleReauth.releaseHTTP")
        wait("Sheet dismissal did not cancel original authenticated transport") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 1); XCTAssertEqual(report()["httpCalls"] as? Int, 1)
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(report()["hasNewSession"] as? Bool, false)
        capture("Actual Apple composition — terminal scoped receipt after physical HTTP return",
                required: [app.staticTexts["appleReauth.report"], begin])
    }
    func testRestartAppleCancellationRequiresFreshConfirmationAndPreservesHeldHTTP() {
        launch("composed", resuming: true)
        XCTAssertEqual(report()["starts"] as? Int, 0)
        XCTAssertEqual(report()["promptID"] as? String, "", "Restart alone cannot present a provider challenge")
        capture("Restart Apple — explicit confirmation with reader startup closed",
                required: [app.buttons["appleReauth.begin"]])
        tap("appleReauth.begin")
        wait("Original resumed action publishes a provider prompt") { ($0["promptID"] as? String)?.isEmpty == false }
        let firstID = report()["promptID"] as? String
        XCTAssertEqual(report()["starts"] as? Int, 0, "The sheet must not launch its provider automatically")
        tap("account.apple.reauthenticate")
        wait("First resumed provider is physically held") { $0["starts"] as? Int == 1 }
        tap("appleReauth.success")
        wait("Original resumed held-user SDK exchange is pending") { $0["sdkHeld"] as? Bool == true && $0["sdkCalls"] as? Int == 1 }
        assertRestartBoundary()
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        XCTAssertEqual(report()["canBeginLedger"] as? Bool, false)
        capture("Restart Apple — held SDK keeps cancellation visible",
                required: [app.buttons["account.apple.reauthenticate"], app.buttons["reauth.apple.cancel"]])
        tap("reauth.apple.cancel")
        wait("Cancellation dismisses the original prompt but keeps physical SDK work") {
            $0["promptID"] as? String == "" && $0["physicalFlight"] as? Bool == true
                && $0["status"] as? String == "cancelled"
        }
        let cancel = app.buttons["reauth.apple.cancel"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        tap("appleReauth.begin")
        wait("Fresh confirmation cannot bypass the cancelled physical SDK slot") { $0["rejectedStarts"] as? Int == 1 }
        tap("appleReauth.releaseSDK")
        wait("Cancelled physical SDK result returns without HTTP") { $0["physicalFlight"] as? Bool == false }
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        tap("appleReauth.begin")
        wait("An explicit new confirmation creates a fresh provider action") {
            let id = $0["promptID"] as? String
            return id?.isEmpty == false && id != firstID
        }
        XCTAssertEqual(report()["starts"] as? Int, 1)
        tap("account.apple.reauthenticate")
        wait("Second original provider starts only after explicit confirmation") { $0["starts"] as? Int == 2 }
        tap("appleReauth.success")
        wait("Fresh held-user SDK exchange is pending") { $0["sdkHeld"] as? Bool == true && $0["sdkCalls"] as? Int == 2 }
        tap("appleReauth.releaseSDK")
        wait("Successful fresh proof dismisses its prompt while original parent HTTP remains held") {
            $0["promptID"] as? String == "" && $0["httpHeld"] as? Bool == true
                && $0["physicalFlight"] as? Bool == true && $0["httpCalls"] as? Int == 1
        }
        let successDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [successDismissed], timeout: 5), .completed)
        assertOriginalParentRequest()
        XCTAssertEqual(report()["hasParentReceipt"] as? Bool, false)
        XCTAssertEqual(report()["canBeginLedger"] as? Bool, false, "Historical ledger checkpoint is not an accepted parent")
        capture("Restart Apple — parent HTTP held after successful sheet dismissal",
                required: [app.buttons["appleReauth.releaseHTTP"], app.staticTexts["appleReauth.report"]])
        tap("appleReauth.releaseHTTP")
        wait("Only a fresh matching parent receipt enables a later explicit ledger action") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
                && $0["hasParentReceipt"] as? Bool == true && $0["canBeginLedger"] as? Bool == true
        }
        assertOriginalParentRequest()
        XCTAssertEqual(report()["httpCalls"] as? Int, 1, "No automatic ledger request")
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        XCTAssertEqual(report()["hasNewSession"] as? Bool, false)
    }

}
