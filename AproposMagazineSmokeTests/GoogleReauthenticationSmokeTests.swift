import XCTest

/// Native UI over the actual Auth/prompt/Google service and held-user/HTTP
/// composition. All provider replies and transports are injected local effects.
final class GoogleReauthenticationSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func launch(_ scenario: String? = nil, resuming: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposGoogleReauthenticationSmoke"]
        if let scenario { app.launchArguments += ["-GoogleReauthenticationScenario", scenario] }
        if resuming { app.launchArguments.append("-AproposDeletionResume") }
        app.launch()
        XCTAssertTrue(app.staticTexts["googleReauth.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["googleReauth.firebase"].label, "Firebase: ikke startet")
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
        let reports = app.staticTexts.matching(identifier: "googleReauth.report").allElementsBoundByIndex
        let visible = reports.first(where: \.isHittable) ?? reports.first
        guard let text = visible?.value as? String, let bytes = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
        return value
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
    private func fullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return element.frame.minX >= app.frame.minX && element.frame.maxX <= app.frame.maxX
            && element.frame.minY >= app.frame.minY && element.frame.maxY <= app.frame.maxY
    }
    private func expose(_ elements: [XCUIElement]) {
        for _ in 0..<6 {
            if elements.allSatisfy({ fullyVisible($0) }) { return }
            let form = app.collectionViews["reauth.google.form"]
            if form.exists { form.swipeUp() } else { app.swipeUp() }
        }
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), id)
        expose([button]); XCTAssertTrue(fullyVisible(button), id); XCTAssertTrue(button.isEnabled, id)
        button.tap()
    }
    private func capture(_ name: String, required: [XCUIElement]) {
        expose(required)
        required.forEach { XCTAssertTrue(fullyVisible($0), $0.identifier) }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let state = XCTAttachment(string: String(describing: report()))
        state.name = name + " — local counters/system text"; state.lifetime = .keepAlways; add(state)
    }
    private func begin() {
        tap("googleReauth.begin")
        wait("Actual Auth publishes the original Google prompt without automatic provider start") {
            ($0["promptID"] as? String)?.isEmpty == false && $0["physicalFlight"] as? Bool == true
        }
        XCTAssertTrue(app.buttons["reauth.google.cancel"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["account.google.reauthenticate"].label, "Bekræft identitet med Google")
        XCTAssertFalse(app.buttons["account.google.signIn"].exists)
    }
    private func waitForDismissal() {
        let cancel = app.buttons["reauth.google.cancel"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    private func completeHeldSDKAndHTTP() {
        tap("googleReauth.success")
        wait("The actual original-user SDK exchange is held") { $0["sdkHeld"] as? Bool == true }
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        XCTAssertFalse(app.buttons["account.google.reauthenticate"].isEnabled)
        XCTAssertTrue(app.buttons["reauth.google.cancel"].isEnabled)
        capture("Google prompt — held SDK with visible confirmation and cancellation",
                required: [app.buttons["account.google.reauthenticate"], app.buttons["reauth.google.cancel"]])
        tap("googleReauth.releaseSDK")
        wait("Successful SDK return dismisses only the original prompt and keeps HTTP physical work") {
            $0["promptID"] as? String == "" && $0["httpHeld"] as? Bool == true
                && $0["httpCalls"] as? Int == 1 && $0["physicalFlight"] as? Bool == true
        }
        waitForDismissal()
        capture("Google prompt — successful dismissal preserves pending HTTP",
                required: [app.buttons["googleReauth.releaseHTTP"], app.staticTexts["googleReauth.report"]])
        tap("googleReauth.releaseHTTP")
        wait("The original HTTP receipt is accepted after sheet dismissal") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["uid"] as? String, "local-reader-A")
        XCTAssertEqual(report()["serviceSignedIn"] as? Bool, false)
        XCTAssertEqual(report()["serviceHasUser"] as? Bool, false)
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }

    func testActualGooglePromptWaitsForSDKAndSuccessDismissalPreservesHTTP() {
        launch(); begin()
        XCTAssertEqual(report()["providerCalls"] as? Int, 0)
        capture("Actual Google prompt — explicit original-action confirmation",
                required: [app.buttons["account.google.reauthenticate"], app.buttons["reauth.google.cancel"]])
        tap("account.google.reauthenticate")
        wait("Exactly one local provider starts") { $0["providerCalls"] as? Int == 1 && $0["working"] as? Bool == true }
        completeHeldSDKAndHTTP()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 1); XCTAssertEqual(report()["httpCalls"] as? Int, 1)
    }

    func testProviderFailureShowsNeutralFeedbackAndRetryCapturesANewOriginalAction() {
        launch(); begin(); let original = report()["promptID"] as? String
        tap("account.google.reauthenticate")
        wait("Original local provider is pending") { $0["providerCalls"] as? Int == 1 }
        tap("googleReauth.failure")
        wait("Completed provider failure settles in the existing deletion coordinator") {
            $0["promptID"] as? String == "" && $0["status"] as? String == "unavailable"
                && $0["physicalFlight"] as? Bool == false
        }
        waitForDismissal()
        let message = app.staticTexts["googleReauth.message"]
        XCTAssertFalse(message.label.contains("PRIVATE")); XCTAssertFalse(message.label.localizedCaseInsensitiveContains("log ind"))
        XCTAssertEqual(message.label, "Anmodningen om læserdata kunne ikke bekræftes. Kontosletning er ikke gennemført.")
        XCTAssertEqual(report()["sdkCalls"] as? Int, 0); XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        capture("Google provider failure — neutral existing coordinator message and explicit retry",
                required: [message, app.buttons["googleReauth.retry"]])
        tap("googleReauth.retry")
        wait("Explicit retry creates a fresh original prompt without replaying credentials") {
            let id = $0["promptID"] as? String
            return id?.isEmpty == false && id != original && ($0["actionIDs"] as? [String])?.count == 2
        }
        XCTAssertEqual(report()["providerCalls"] as? Int, 1)
        tap("account.google.reauthenticate")
        wait("Fresh prompt starts its own local provider") { $0["providerCalls"] as? Int == 2 }
        completeHeldSDKAndHTTP()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 1)
    }

    func testCancelDismissesOriginalPromptButKeepsPhysicalProviderUntilLateCallback() {
        launch(); begin(); tap("account.google.reauthenticate")
        wait("Original provider is physically held") { $0["providerCalls"] as? Int == 1 && $0["working"] as? Bool == true }
        capture("Google provider held — cancellation stays available",
                required: [app.buttons["account.google.reauthenticate"], app.buttons["reauth.google.cancel"]])
        tap("reauth.google.cancel")
        wait("Logical cancellation closes only the original prompt") {
            $0["promptID"] as? String == "" && $0["physicalFlight"] as? Bool == true
                && $0["status"] as? String == "cancelled"
        }
        waitForDismissal()
        tap("googleReauth.begin")
        wait("A new action cannot bypass the held original provider") { $0["rejectedStarts"] as? Int == 1 }
        XCTAssertEqual(report()["providerCalls"] as? Int, 1)
        tap("googleReauth.success")
        wait("Late provider callback drains without constructing an SDK exchange") {
            $0["physicalFlight"] as? Bool == false && $0["sdkCalls"] as? Int == 0 && $0["httpCalls"] as? Int == 0
        }
        XCTAssertEqual(report()["status"] as? String, "cancelled")
        XCTAssertEqual(report()["uid"] as? String, "local-reader-A")
        XCTAssertEqual(report()["serviceSignedIn"] as? Bool, false)
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        capture("Google provider cancellation — original callback has drained without login",
                required: [app.staticTexts["googleReauth.report"]])
    }

    func testExistingLoginInitializerRendersUnchangedWithoutStartingAProvider() {
        launch("loginRender")
        let button = app.buttons["account.google.signIn"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.label, "Fortsæt med Google")
        let category = report()["systemCategory"] as? String ?? ""
        XCTAssertFalse(category.isEmpty)
        if category.localizedCaseInsensitiveContains("accessibility") {
            XCTAssertGreaterThan(button.frame.height, 50, "Large multiline text must grow beyond the old clipping frame")
        } else {
            XCTAssertEqual(button.frame.height, 50, accuracy: 1, "Normal button geometry must remain unchanged")
        }
        XCTAssertFalse(app.buttons["account.google.reauthenticate"].exists)
        capture("Existing Google login button — disabled render with no service work", required: [button])
        XCTAssertEqual(report()["providerCalls"] as? Int, 0); XCTAssertEqual(report()["sdkCalls"] as? Int, 0)
        XCTAssertEqual(report()["httpCalls"] as? Int, 0); XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }
    func testRestartGoogleCancellationRequiresFreshConfirmationAndPreservesHeldHTTP() {
        launch(resuming: true)
        XCTAssertEqual(report()["providerCalls"] as? Int, 0)
        XCTAssertEqual(report()["promptID"] as? String, "", "Restart alone cannot present a provider challenge")
        capture("Restart Google — explicit confirmation with reader startup closed",
                required: [app.buttons["googleReauth.begin"]])
        tap("googleReauth.begin")
        wait("Original resumed action publishes a provider prompt") { ($0["promptID"] as? String)?.isEmpty == false }
        let firstID = report()["promptID"] as? String
        XCTAssertEqual(report()["providerCalls"] as? Int, 0, "The sheet must not launch its provider automatically")
        tap("account.google.reauthenticate")
        wait("First resumed provider is physically held") { $0["providerCalls"] as? Int == 1 }
        tap("googleReauth.success")
        wait("Original resumed held-user SDK exchange is pending") { $0["sdkHeld"] as? Bool == true && $0["sdkCalls"] as? Int == 1 }
        assertRestartBoundary()
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        XCTAssertEqual(report()["canBeginLedger"] as? Bool, false)
        capture("Restart Google — held SDK keeps cancellation visible",
                required: [app.buttons["account.google.reauthenticate"], app.buttons["reauth.google.cancel"]])
        tap("reauth.google.cancel")
        wait("Cancellation dismisses the original prompt but keeps physical SDK work") {
            $0["promptID"] as? String == "" && $0["physicalFlight"] as? Bool == true
                && $0["status"] as? String == "cancelled"
        }
        let cancel = app.buttons["reauth.google.cancel"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        tap("googleReauth.begin")
        wait("Fresh confirmation cannot bypass the cancelled physical SDK slot") { $0["rejectedStarts"] as? Int == 1 }
        tap("googleReauth.releaseSDK")
        wait("Cancelled physical SDK result returns without HTTP") { $0["physicalFlight"] as? Bool == false }
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
        tap("googleReauth.begin")
        wait("An explicit new confirmation creates a fresh provider action") {
            let id = $0["promptID"] as? String
            return id?.isEmpty == false && id != firstID
        }
        XCTAssertEqual(report()["providerCalls"] as? Int, 1)
        tap("account.google.reauthenticate")
        wait("Second original provider starts only after explicit confirmation") { $0["providerCalls"] as? Int == 2 }
        tap("googleReauth.success")
        wait("Fresh held-user SDK exchange is pending") { $0["sdkHeld"] as? Bool == true && $0["sdkCalls"] as? Int == 2 }
        tap("googleReauth.releaseSDK")
        wait("Successful fresh proof dismisses its prompt while original parent HTTP remains held") {
            $0["promptID"] as? String == "" && $0["httpHeld"] as? Bool == true
                && $0["physicalFlight"] as? Bool == true && $0["httpCalls"] as? Int == 1
        }
        let successDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [successDismissed], timeout: 5), .completed)
        assertOriginalParentRequest()
        XCTAssertEqual(report()["hasParentReceipt"] as? Bool, false)
        XCTAssertEqual(report()["canBeginLedger"] as? Bool, false, "Historical ledger checkpoint is not an accepted parent")
        capture("Restart Google — parent HTTP held after successful sheet dismissal",
                required: [app.buttons["googleReauth.releaseHTTP"], app.staticTexts["googleReauth.report"]])
        tap("googleReauth.releaseHTTP")
        wait("Only a fresh matching parent receipt enables a later explicit ledger action") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
                && $0["hasParentReceipt"] as? Bool == true && $0["canBeginLedger"] as? Bool == true
        }
        assertOriginalParentRequest()
        XCTAssertEqual(report()["httpCalls"] as? Int, 1, "No automatic ledger request")
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        XCTAssertEqual(report()["serviceSignedIn"] as? Bool, false)
        XCTAssertEqual(report()["serviceHasUser"] as? Bool, false)
    }

}
