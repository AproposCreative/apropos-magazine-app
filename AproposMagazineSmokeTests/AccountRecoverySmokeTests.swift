import XCTest

/// Native account content and real Auth-owned recovery composition, entirely
/// local. This is not provider, deployed endpoint, or completed-account acceptance.
final class AccountRecoverySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var capturePrerequisiteDisclosures = true
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ scenario: String) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposAccountRecoverySmoke", "-AccountRecoveryScenario", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["accountRecovery.firebase"].waitForExistence(timeout: 8))
        wait("Actual local disk/startup preparation completes") { $0["ready"] as? Bool == true }
        assertClosedReader()
    }
    private func report() -> [String: Any] {
        let values = app.staticTexts.matching(identifier: "accountRecovery.report").allElementsBoundByIndex
        let value = values.first(where: \.isHittable) ?? values.first
        guard let text = value?.value as? String, let data = text.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    private func wait(_ message: String, _ predicate: @escaping ([String: Any]) -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }; return predicate(self.report())
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        if result != .completed { attach(message) }
        XCTAssertEqual(result, .completed, message)
    }
    private func assertClosedReader() {
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(report()["readerUnresolved"] as? Bool, true)
        XCTAssertEqual(report()["bootstrapUID"] as? String, "local-reader-A")
        XCTAssertEqual(report()["readerEffects"] as? Int, 0)
        XCTAssertEqual(report()["preferenceEffects"] as? Int, 0)
        XCTAssertEqual(report()["complete"] as? Bool, false)
    }
    private func formBounds() -> (form: XCUIElement, top: CGFloat, bottom: CGFloat)? {
        let reauth = app.collectionViews["reauth.form"]
        let account = app.collectionViews["reader.account.form"]
        let form = reauth.exists ? reauth : account
        guard form.exists else { return nil }
        let bar = app.navigationBars[reauth.exists ? "Bekræft identitet" : "Din konto"]
        var top = max(form.frame.minY + 8, app.frame.minY)
        if bar.exists { top = max(top, bar.frame.maxY + 8) }
        var bottom = min(form.frame.maxY - 8, app.frame.maxY - 12)
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
        if !reauth.exists, app.otherElements["accountRecovery.controls"].exists {
            bottom = min(bottom, app.otherElements["accountRecovery.controls"].frame.minY)
        }
        return (form, top, bottom)
    }
    private func visible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        var top = app.frame.minY, bottom = app.frame.maxY - 12
        // Form content must be entirely below the real navigation bar and
        // above the measured footer/keyboard. Modal and toolbar buttons are
        // outside that viewport and still require their full screen frame.
        let id = element.identifier
        if ["E-mail og adgangskode", "Apple", "Google"].contains(id)
            || (id == "reader.recovery.confirm" && app.alerts.firstMatch.exists)
            || (id == "Annuller" && (app.alerts["Fjern læsepositioner?"].exists || app.alerts["Fjern lyttepositioner?"].exists
                || app.alerts["Fjern introduktionsudkast?"].exists || app.alerts["Fjern lokal læsehistorik?"].exists)) {
            let modal = modalScrollBounds(toward: element)
            guard modal.presented, let viewport = modal.frame else { return false }
            return viewport.contains(element.frame)
        }
        let inForm = (id.hasPrefix("reader.recovery.") && id != "reader.recovery.confirm")
            || id.hasPrefix("account.")
        if inForm, let bounds = formBounds() { top = bounds.top; bottom = bounds.bottom }
        return element.frame.minX >= app.frame.minX && element.frame.maxX <= app.frame.maxX
            && element.frame.minY >= top && element.frame.maxY <= bottom
    }
    private func modalScrollBounds(toward target: XCUIElement?) -> (presented: Bool, frame: CGRect?) {
        let providers = ["E-mail og adgangskode", "Apple", "Google"]
        let providerDialog = providers.allSatisfy { app.buttons[$0].exists }
        let modalTypes: [XCUIElement.ElementType] = [.alert, .sheet, .popover, .dialog]
        let modals = modalTypes.flatMap { app.descendants(matching: $0).allElementsBoundByIndex }
        // A lazy Form row can be absent during bounded scroll discovery.
        // Asking its identifier before it exists fails the AX snapshot.
        let identifier = target.flatMap { $0.exists ? $0.identifier : nil }
        let screen = app.frame
        let matchingModals = modals.filter { modal in
            guard modal.exists, modal.frame.minX > screen.minX, modal.frame.maxX < screen.maxX else { return false }
            if providerDialog { return providers.allSatisfy { modal.buttons[$0].exists } }
            guard let identifier, !identifier.isEmpty else { return false }
            return modal.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
        }
        guard providerDialog || !matchingModals.isEmpty else { return (false, nil) }

        // Prefer the actual scrolling viewport, rather than the popover's
        // title or the account Form behind it. Root/screen-sized ancestors
        // are never accepted as a substitute for a missing modal container.
        let scrolls = app.scrollViews.allElementsBoundByIndex.filter { view in
            guard view.exists else { return false }
            if providerDialog { return providers.allSatisfy { view.buttons[$0].exists } }
            guard let identifier, !identifier.isEmpty else { return false }
            return view.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
        }
        func viewport(_ element: XCUIElement) -> CGRect? {
            let frame = element.frame
            guard frame.width > 60, frame.height > 60,
                  frame.minX > screen.minX, frame.maxX < screen.maxX,
                  frame.minY >= screen.minY, frame.maxY <= screen.maxY else { return nil }
            return frame
        }
        if let frame = scrolls.compactMap(viewport).min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return (true, frame)
        }
        guard var frame = matchingModals.compactMap(viewport).min(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return (true, nil)
        }
        if providerDialog {
            // Some OS versions expose the dialog but omit its scroll view.
            // Keep the gesture below the actual first action, outside the
            // separate, non-scrolling title. These are measured AX frames.
            let bottom = frame.maxY
            let top = max(frame.minY, providers.map { app.buttons[$0].frame.minY }.min() ?? frame.minY)
            frame = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
        }
        return (true, frame.height > 60 ? frame : nil)
    }
    @discardableResult
    private func scrollForm(toward target: XCUIElement? = nil, settled: Bool = false) -> Bool {
        let modal = modalScrollBounds(toward: target)
        if modal.presented {
            guard let frame = modal.frame else {
                attach("Modal scroll viewport could not be identified")
                XCTFail("Refusing to scroll the background Form while a modal is presented")
                return false
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let movingDown = target.map { $0.exists && $0.frame.minY < frame.minY } ?? false
            let startY = frame.minY + frame.height * (movingDown ? 0.15 : 0.85)
            let endY = frame.minY + frame.height * (movingDown ? 0.85 : 0.15)
            origin.withOffset(CGVector(dx: frame.midX, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: endY)))
            return true
        }
        guard let bounds = formBounds() else {
            attach("Form scroll viewport could not be identified")
            XCTFail("No known scroll viewport")
            return false
        }
        let height = bounds.bottom - bounds.top
        XCTAssertGreaterThan(height, 60)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // Capture discovery follows the content, away from the native scroll
        // indicator's expanded hit area. Stop before release so a lazy row is
        // measured at its settled position instead of during deceleration.
        let x = settled ? bounds.form.frame.midX : bounds.form.frame.maxX - 24
        var startY = bounds.top + height * 0.85
        var endY = bounds.top + height * 0.15
        var correcting = false
        if let target, target.exists {
            if target.frame.minY < bounds.top || target.frame.maxY > bounds.bottom {
                let correction = max(-height * 0.6, min(height * 0.6,
                    (bounds.top + bounds.bottom) / 2 - target.frame.midY))
                startY = bounds.top + height * (correction > 0 ? 0.15 : 0.85)
                endY = startY + correction
                correcting = true
            }
        }
        // Preserve the established discovery gesture; measured corrections
        // can move either way without overscrolling a nearly full-height row.
        let start = origin.withOffset(CGVector(dx: x, dy: startY))
        let end = origin.withOffset(CGVector(dx: x, dy: endY))
        if correcting || settled {
            // Stop the finger before release so kinetic scrolling cannot
            // oscillate past a large label that only narrowly fits the viewport.
            start.press(forDuration: 0.05, thenDragTo: end,
                withVelocity: .slow, thenHoldForDuration: 0.3)
        } else {
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return true
    }
    private func expose(_ element: XCUIElement) {
        // A lazy Form row at large text may not enter the AX tree until a
        // real scroll brings it into the viewport. Discovery is bounded too.
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<7 { if visible(element) { break }; if !scrollForm(toward: element, settled: true) { break } }
        guard element.exists else {
            attach("Requested control absent after bounded settled discovery")
            XCTFail("The requested control did not enter the accessibility tree")
            return
        }
        if !visible(element) { attach("Control not fully exposed: " + element.identifier) }
        XCTAssertTrue(visible(element), element.identifier)
    }
    private func tap(_ id: String) {
        let matches = app.buttons.matching(identifier: id)
        _ = matches.firstMatch.waitForExistence(timeout: 5)
        for attempt in 0...7 {
            // A dismissing sheet can briefly retain an inaccessible duplicate.
            // Only the fully exposed, hittable control may receive the action.
            if let button = matches.allElementsBoundByIndex.first(where: { visible($0) }) {
                XCTAssertTrue(button.isEnabled, id); button.tap(); return
            }
            if attempt < 7, !scrollForm(toward: matches.allElementsBoundByIndex.first) { break }
        }
        attach("Control not fully exposed: " + id)
        XCTFail("No fully visible, hittable control: " + id)
    }
    private func waitForAlertDismissal(_ title: String) {
        let alert = app.alerts[title]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !alert.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let state = XCTAttachment(string: String(describing: report()) + "\n" + app.debugDescription)
        state.name = name + " — local evidence"; state.lifetime = .keepAlways; add(state)
    }
    private func capture(_ name: String, element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        // A new section can still be virtualized after its prerequisite row
        // changes height. Discover it with bounded nonkinetic content drags,
        // then choose full-control versus long-paragraph coverage from the
        // actual settled frame. Never infer paragraph size from an absent row.
        for _ in 0..<7 {
            if element.exists { break }
            if !scrollForm(toward: element, settled: true) { break }
        }
        guard element.exists else {
            attach(name + " — requested element absent after bounded discovery")
            XCTFail("Cannot capture the requested element before it exists")
            return
        }
        if element.elementType == .staticText,
           let bounds = formBounds(), element.frame.height > bounds.bottom - bounds.top {
            captureLongParagraph(name, element: element)
        } else {
            expose(element); attach(name)
        }
    }
    private func captureLongParagraph(_ name: String, element: XCUIElement) {
        // At maximum text a paragraph may exceed one viewport. Prove both
        // edges and overlapping coverage by real scrolling; never use this
        // path for buttons or fields, which must remain fully exposed.
        let originalLabel = element.label, originalHeight = element.frame.height
        var capturedFrames: [CGRect] = []
        var coverage: [ClosedRange<CGFloat>] = []
        for showStart in [true, false] {
            var aligned = false
            for attempt in 0...7 {
                guard let bounds = formBounds() else { XCTFail("Missing paragraph viewport"); return }
                let frame = element.frame, height = bounds.bottom - bounds.top
                let edgeVisible = showStart
                    ? frame.minY >= bounds.top && frame.minY < bounds.top + height / 3
                    : frame.maxY <= bounds.bottom && frame.maxY > bounds.bottom - height / 3
                if element.isHittable && edgeVisible {
                    XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX)
                    XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX)
                    XCTAssertEqual(element.label, originalLabel)
                    XCTAssertEqual(frame.height, originalHeight, accuracy: 0.5)
                    coverage.append(max(0, bounds.top - frame.minY)...min(originalHeight, bounds.bottom - frame.minY))
                    capturedFrames.append(frame)
                    attach(name + (showStart ? " — paragraph start" : " — paragraph end"))
                    aligned = true; break
                }
                // Inspect the final settled result too. There are still at
                // most seven gestures; a successful seventh drag must not
                // be reported as an unreadable edge without being checked.
                if attempt == 7 { break }
                let delta = showStart ? bounds.top + 16 - frame.minY : bounds.bottom - 16 - frame.maxY
                // Cross UIKit's gesture threshold even for a nearly aligned
                // edge, then stop before lifting to avoid kinetic overshoot.
                let movement = max(-height * 0.6, min(height * 0.6, delta + (delta > 0 ? 20 : -20)))
                let startY = bounds.top + height * (movement > 0 ? 0.15 : 0.85)
                // Follow the content rather than the expanded native scroll
                // indicator hit area, as in settled Form discovery above.
                let origin = app.coordinate(withNormalizedOffset: .zero), x = bounds.form.frame.midX
                origin.withOffset(CGVector(dx: x, dy: startY)).press(forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: x, dy: startY + movement)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            if !aligned { attach(name + " — paragraph edge unavailable") }
            XCTAssertTrue(aligned, "Both paragraph edges must be readable")
        }
        guard coverage.count == 2, capturedFrames.count == 2 else { return }
        XCTAssertEqual(coverage[0].lowerBound, 0)
        XCTAssertEqual(coverage[1].upperBound, originalHeight, accuracy: 0.5)
        XCTAssertLessThan(coverage[1].lowerBound, coverage[0].upperBound, "The two visible text intervals must overlap")
        XCTAssertGreaterThan(abs(capturedFrames[0].minY - capturedFrames[1].minY), 1, "The paragraph was actually scrolled")
    }
    private func open() { tap("accountRecovery.open"); XCTAssertTrue(app.collectionViews["reader.account.form"].waitForExistence(timeout: 5)) }
    private func chooseEmail() {
        tap("reader.recovery.begin")
        tap("E-mail og adgangskode")
        XCTAssertTrue(app.alerts["Genoptag din anmodning?"].waitForExistence(timeout: 5))
    }
    private func confirm() {
        tap("reader.recovery.confirm")
        let passwordExists = app.secureTextFields["account.password"].waitForExistence(timeout: 5)
        if !passwordExists { attach("Confirmed original action did not present the actual password form") }
        XCTAssertTrue(passwordExists)
        XCTAssertEqual(app.staticTexts["account.lockedEmail"].label, "original.reader@example.invalid")
        XCTAssertFalse(app.buttons["account.google.signIn"].exists)
        XCTAssertFalse(app.buttons["account.apple.signIn"].exists)
    }
    private func passwordAndSubmit(expectHeldHTTP: Bool = true) {
        let field = app.secureTextFields["account.password"]; expose(field)
        let value = field.value as? String
        XCTAssertTrue(value == nil || value == "" || value == "Adgangskode", "Each explicit action has a fresh password draft")
        field.tap(); field.typeText("Local123!")
        capture("Actual recovery — full identity confirmation before submit", element: app.buttons["account.submit"])
        tap("account.submit")
        wait("Prompt retires after the local SDK result; only an accepted original selection reaches HTTP") {
            guard $0["promptID"] as? String == "" else { return false }
            if expectHeldHTTP { return $0["httpHeld"] as? Bool == true && $0["physicalFlight"] as? Bool == true }
            return $0["pushStatus"] as? String == "unavailable" && $0["httpHeld"] as? Bool == false
                && $0["physicalFlight"] as? Bool == false
        }
        let cancel = app.buttons["reauth.cancel"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cancel.exists }, object: nil)], timeout: 5), .completed)
    }

    func testCheckpointWithoutEndpointShowsHonestStatusAndStartsNothing() {
        launch("nilConfiguration"); open()
        capture("Checkpoint exists — configured resumption is unavailable", element: app.staticTexts["reader.recovery.notConfigured"])
        XCTAssertFalse(app.buttons["reader.recovery.begin"].exists)
        XCTAssertFalse(app.buttons["reader.recovery.retry"].exists)
        XCTAssertFalse(app.staticTexts["accountRecovery.guest"].exists)
        for counter in ["factoryCalls", "sdkCalls", "httpCalls"] { XCTAssertEqual(report()[counter] as? Int, 0) }
        tap("accountRecovery.close"); open()
        XCTAssertTrue(app.staticTexts["reader.recovery.notConfigured"].exists)
        assertClosedReader()
    }

    func testGenericSealAndCorruptCheckpointRemainDistinctWithoutRecoveryActions() {
        for (scenario, identifier) in [("genericSeal", "reader.recovery.protected"), ("corrupt", "reader.recovery.unavailable")] {
            launch(scenario); open()
            capture("Closed account — " + scenario, element: app.staticTexts[identifier])
            XCTAssertFalse(app.staticTexts["reader.recovery.deletion"].exists)
            XCTAssertFalse(app.buttons["reader.recovery.begin"].exists)
            for counter in ["factoryCalls", "sdkCalls", "httpCalls"] { XCTAssertEqual(report()[counter] as? Int, 0) }
            assertClosedReader()
        }
    }

    func testExplicitRecoveryRetainsFlowAcrossErrorCancelReopenAndSeparatelyConfirmsLedger() {
        launch("configured"); open()
        tap("reader.recovery.begin"); tap("Google"); tap("reader.recovery.confirm")
        capture("Unsupported provider — original account can still choose its existing method",
                element: app.staticTexts["reader.recovery.providerUnavailable"])
        XCTAssertEqual(report()["factoryCalls"] as? Int, 0)
        chooseEmail(); app.alerts["Genoptag din anmodning?"].buttons["Annuller"].tap()
        waitForAlertDismissal("Genoptag din anmodning?")
        XCTAssertEqual(report()["factoryCalls"] as? Int, 0, "Provider choice is not final confirmation")
        chooseEmail(); confirm(); passwordAndSubmit()
        let originalFlow = report()["flowID"] as? String
        XCTAssertFalse(originalFlow?.isEmpty ?? true)
        tap("accountRecovery.releaseHTTP")
        wait("Actual local transport failure is presented by the retained coordinator") {
            $0["status"] as? String == "unavailable" && $0["physicalFlight"] as? Bool == false
        }
        capture("Recovery — neutral failure with explicit retry", element: app.staticTexts["reader.recovery.status"])
        XCTAssertFalse(app.buttons["reader.recovery.ledger"].exists)
        tap("reader.recovery.cancel")
        wait("Explicit cancellation retains the owned flow and original family") { $0["status"] as? String == "cancelled" }
        tap("accountRecovery.close"); open()
        XCTAssertEqual(report()["flowID"] as? String, originalFlow)
        XCTAssertEqual(report()["factoryCalls"] as? Int, 1)
        tap("reader.recovery.retry"); confirm(); passwordAndSubmit()
        tap("accountRecovery.releaseHTTP")
        wait("Fresh parent receipt enables only the separately confirmed next phase") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        capture("Partial parent completion — ledger remains an explicit action", element: app.staticTexts["reader.recovery.status"])
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        tap("reader.recovery.ledger")
        XCTAssertTrue(app.alerts["Fortsæt oprydningen?"].waitForExistence(timeout: 5))
        confirm(); passwordAndSubmit()
        tap("accountRecovery.releaseHTTP")
        wait("Original ledger receipt remains explicitly partial") {
            $0["status"] as? String == "ledgerDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["flowID"] as? String, originalFlow)
        XCTAssertEqual(report()["factoryCalls"] as? Int, 1)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 3)
        XCTAssertEqual(report()["sentScopes"] as? [String], ["parent", "parent", "ledger"])
        let ids = report()["sentIDs"] as? [String] ?? []
        XCTAssertEqual(ids.count, 3); XCTAssertEqual(Set(ids).count, 1)
        let actions = report()["actionIDs"] as? [String] ?? []
        XCTAssertEqual(actions.count, 3); XCTAssertEqual(Set(actions).count, 3)
        capture("Ledger receipt — no claim of complete account deletion", element: app.staticTexts["reader.recovery.status"])
        XCTAssertFalse(app.buttons["reader.recovery.ledger"].exists)
        assertClosedReader()
    }

    func testAccountRoundTripRetiresOldConfirmationWithoutCreatingAProvider() {
        launch("accountRoundTrip"); open(); tap("accountRecovery.armRoundTrip")
        XCTAssertEqual(report()["factoryCalls"] as? Int, 0)
        chooseEmail()
        XCUIDevice.shared.press(.home); app.activate()
        wait("Actual Auth A to B to A changes the original confirmation generation") { $0["roundTrips"] as? Int == 1 }
        waitForAlertDismissal("Genoptag din anmodning?")
        XCTAssertFalse(app.alerts["Genoptag din anmodning?"].exists)
        for counter in ["factoryCalls", "sdkCalls", "httpCalls"] { XCTAssertEqual(report()[counter] as? Int, 0) }
        assertClosedReader()
        chooseEmail(); confirm()
        capture("New account generation — fresh explicit challenge", element: app.buttons["reauth.cancel"])
        tap("reauth.cancel")
        wait("Fresh challenge can be explicitly cancelled without a credential exchange") { $0["status"] as? String == "cancelled" }
        XCTAssertEqual(report()["factoryCalls"] as? Int, 1)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 0)
        XCTAssertEqual(report()["httpCalls"] as? Int, 0)
    }

    private func completeOriginalCloudPhasesForLocalCleanup(expectedHTTPCalls: Int = 2, expectedSDKCalls: Int = 2) {
        open(); chooseEmail(); confirm(); passwordAndSubmit()
        tap("accountRecovery.releaseHTTP")
        wait("The original parent completes before any local cleanup is available") {
            $0["status"] as? String == "scopedCloudDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["localJournalFactoryCalls"] as? Int, 0)
        XCTAssertEqual(report()["ownV1"] as? Bool, true)
        XCTAssertEqual(report()["ownV2"] as? Bool, true)
        tap("reader.recovery.ledger"); confirm(); passwordAndSubmit()
        tap("accountRecovery.releaseHTTP")
        wait("The accepted ledger receipt does not automatically remove local choices") {
            $0["status"] as? String == "ledgerDataRemoved" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["httpCalls"] as? Int, expectedHTTPCalls)
        XCTAssertEqual(report()["sdkCalls"] as? Int, expectedSDKCalls)
        XCTAssertEqual(report()["localJournalFactoryCalls"] as? Int, 0)
        XCTAssertEqual(report()["localRemoveStarts"] as? Int, 0)
        XCTAssertEqual(report()["ownV1"] as? Bool, true)
        XCTAssertEqual(report()["ownV2"] as? Bool, true)
        assertLocalOtherOwnersPreserved()
    }

    private func assertLocalOtherOwnersPreserved() {
        XCTAssertEqual(report()["otherUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["guestUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["recoveryClosed"] as? Bool, true)
        assertClosedReader()
    }

    private func captureLocalCleanupDisclosure(
        title: String = "Fjern gemte artikelvalg?",
        label: String = "Fjern denne kontos gemte artikelvalg fra enheden. Andre kontis valg og Research bevares. Downloadede artikler, andre enheder og de øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført."
    ) {
        // New history scenarios still execute every real prior action and
        // state assertion. Their prior disclosure coverage is provided by the
        // unchanged dedicated tests; avoid repeating those long captures.
        guard capturePrerequisiteDisclosures else { return }
        let alert = app.alerts[title]
        let predicate = NSPredicate(format: "label == %@", label)
        let message = alert.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        guard let viewport = alert.scrollViews.allElementsBoundByIndex.first(where: {
            $0.staticTexts.matching(predicate).firstMatch.exists
        }) else {
            XCTAssertTrue(alert.frame.contains(message.frame))
            attach("Local confirmation — complete disclosure")
            return
        }
        let originalHeight = message.frame.height
        XCTAssertGreaterThan(originalHeight, 0)
        var covered: CGFloat = 0
        for portion in 0..<10 {
            let bounds = viewport.frame, frame = message.frame
            XCTAssertEqual(message.label, label)
            XCTAssertEqual(frame.height, originalHeight, accuracy: 1)
            XCTAssertGreaterThan(bounds.height, 60)
            let alertFrame = alert.frame
            let excursion = max(0, alertFrame.minX - bounds.minX, alertFrame.minY - bounds.minY,
                                bounds.maxX - alertFrame.maxX, bounds.maxY - alertFrame.maxY)
            let geometry = XCTAttachment(string: "alert=\(alertFrame); viewport=\(bounds); message=\(frame); edgeExcursion=\(excursion)")
            geometry.name = "Local disclosure geometry \(portion + 1)"
            geometry.lifetime = .keepAlways
            add(geometry)
            // Both selected iPhones have 3x displays. AX fractional point
            // arithmetic must remain within one actual display pixel.
            XCTAssertLessThanOrEqual(excursion, 1.0 / 3.0)
            XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
            XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
            let lower = max(0, bounds.minY - frame.minY)
            let upper = min(originalHeight, bounds.maxY - frame.minY)
            XCTAssertGreaterThan(upper, lower)
            XCTAssertLessThanOrEqual(lower, covered + 1, "Disclosure captures must overlap")
            attach("Local confirmation — disclosure portion \(portion + 1)")
            covered = max(covered, upper)
            if covered >= originalHeight - 1 { return }
            // The native alert keeps actions in a separate scroll view.
            // Scroll only the measured message viewport, never the Form.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX, dy: bounds.minY + bounds.height * 0.85))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: bounds.minY + bounds.height * 0.25)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("The full local-cleanup disclosure was not exposed")
    }

    private func prepareAndConfirmLocalCleanup() {
        tap("reader.recovery.localFavorites.begin")
        XCTAssertTrue(app.alerts["Fjern gemte artikelvalg?"].waitForExistence(timeout: 5))
        wait("Only a prepared original local snapshot can be confirmed") {
            $0["localStatus"] as? String == "ready" && $0["localConfirmation"] as? Bool == true
        }
        captureLocalCleanupDisclosure()
        // The native alert exposes a nested Button wrapper with the same ID.
        // Keep full-visibility assertions while selecting one concrete element.
        capture("Separate device-local choice confirmation", element: app.alerts["Fjern gemte artikelvalg?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        tap("reader.recovery.confirm")
        waitForAlertDismissal("Fjern gemte artikelvalg?")
    }

    func testLocalFavoritesRequireSeparateConfirmationAndRemoveOnlyOriginalOwner() {
        launch("localFavorites"); completeOriginalCloudPhasesForLocalCleanup()
        capture("Cloud receipt does not erase device choices", element: app.buttons["reader.recovery.localFavorites.begin"])
        tap("reader.recovery.localFavorites.begin")
        XCTAssertTrue(app.alerts["Fjern gemte artikelvalg?"].waitForExistence(timeout: 5))
        app.alerts["Fjern gemte artikelvalg?"].buttons["Annuller"].tap()
        waitForAlertDismissal("Fjern gemte artikelvalg?")
        wait("Cancelling the local confirmation keeps both original formats") {
            $0["localStatus"] as? String == "cancelled" && $0["localRemoveStarts"] as? Int == 0
        }
        XCTAssertEqual(report()["ownV1"] as? Bool, true)
        XCTAssertEqual(report()["ownV2"] as? Bool, true)
        prepareAndConfirmLocalCleanup()
        wait("The actual journal remove is held with no completed local claim") {
            $0["localStatus"] as? String == "removing" && $0["localRemoveHeld"] as? Bool == true
        }
        capture("Device-local removal waits for the physical file operation", element: app.staticTexts["reader.recovery.localFavorites.status"])
        XCTAssertFalse(app.staticTexts["reader.recovery.localFavorites.partial"].exists)
        assertLocalOtherOwnersPreserved()
        tap("accountRecovery.releaseLocal")
        wait("Readback confirms both original formats were removed") {
            $0["localStatus"] as? String == "removed" && $0["ownV1"] as? Bool == false && $0["ownV2"] as? Bool == false
        }
        capture("Original local choices removed; account deletion remains incomplete", element: app.staticTexts["reader.recovery.localFavorites.status"])
        capture("Remaining account work is still explicit", element: app.staticTexts["reader.recovery.localFavorites.partial"])
        XCTAssertFalse(app.buttons["reader.recovery.localFavorites.begin"].exists)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        XCTAssertEqual(report()["localJournalFactoryCalls"] as? Int, 1)
        assertLocalOtherOwnersPreserved()
        tap("accountRecovery.close"); open()
        wait("Reopening the existing account flow preserves the local result") { $0["localStatus"] as? String == "removed" }
        assertLocalOtherOwnersPreserved()
    }

    func testPartialLocalFavoritesFailureRequiresFreshConfirmationAndCompletesExactRetry() {
        launch("localFavoritesFailure"); completeOriginalCloudPhasesForLocalCleanup()
        prepareAndConfirmLocalCleanup()
        wait("Actual local file operation waits before the injected second-format failure") { $0["localRemoveHeld"] as? Bool == true }
        tap("accountRecovery.releaseLocal")
        wait("V2 is physically removed, but failed V1 removal cannot claim completion") {
            $0["localStatus"] as? String == "failed" && $0["ownV2"] as? Bool == false && $0["ownV1"] as? Bool == true
        }
        capture("Partial local failure — explicit retry without a full deletion claim", element: app.staticTexts["reader.recovery.localFavorites.status"])
        XCTAssertFalse(app.staticTexts["reader.recovery.localFavorites.partial"].exists)
        XCTAssertEqual(report()["localConfirmation"] as? Bool, false)
        assertLocalOtherOwnersPreserved()
        prepareAndConfirmLocalCleanup()
        wait("A newly confirmed retry finishes the exact original local pair") {
            $0["localStatus"] as? String == "removed" && $0["ownV1"] as? Bool == false && $0["ownV2"] as? Bool == false
        }
        capture("Local retry complete — other account work remains", element: app.staticTexts["reader.recovery.localFavorites.status"])
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        XCTAssertEqual(report()["localJournalFactoryCalls"] as? Int, 1)
        assertLocalOtherOwnersPreserved()
    }

    private var resumeDisclosure: String {
        "Fjern denne kontos gemte læsepositioner fra enheden. Andre kontis og gæstens positioner samt Research bevares. Læsehistorik i iCloud, lyttepositioner, downloads og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført."
    }

    private func assertResumeOtherOwnersPreserved() {
        XCTAssertEqual(report()["resumeOtherUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["resumeGuestUnchanged"] as? Bool, true)
        assertLocalOtherOwnersPreserved()
    }

    private func completeOriginalFavoritesBeforeResumeCleanup() {
        completeOriginalCloudPhasesForLocalCleanup()
        XCTAssertFalse(app.buttons["reader.recovery.localResume.begin"].exists)
        XCTAssertEqual(report()["resumeOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 0)
        prepareAndConfirmLocalCleanup()
        wait("Favorites removal remains a separate physical operation") { $0["localRemoveHeld"] as? Bool == true }
        tap("accountRecovery.releaseLocal")
        wait("Only the accepted favorites receipt opens the separate resume option") {
            $0["localStatus"] as? String == "removed" && $0["ownV1"] as? Bool == false && $0["ownV2"] as? Bool == false
        }
        XCTAssertEqual(report()["resumeOwnerCount"] as? Int, 2, "Favorites cleanup must not remove reading anchors")
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 0)
        XCTAssertEqual(report()["resumeStatus"] as? String, "idle")
        assertResumeOtherOwnersPreserved()
    }

    private func prepareLocalResumeCleanup() {
        tap("reader.recovery.localResume.begin")
        XCTAssertTrue(app.alerts["Fjern læsepositioner?"].waitForExistence(timeout: 5))
        wait("A newly prepared owner-specific resume snapshot requires explicit confirmation") {
            $0["resumeStatus"] as? String == "ready" && $0["resumeConfirmation"] as? Bool == true
        }
        captureLocalCleanupDisclosure(title: "Fjern læsepositioner?", label: resumeDisclosure)
    }

    private func confirmLocalResumeCleanup() {
        capture("Separate reading-position confirmation", element: app.alerts["Fjern læsepositioner?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        tap("reader.recovery.confirm")
        waitForAlertDismissal("Fjern læsepositioner?")
    }

    func testLocalResumeCleanupRequiresFreshConfirmationAndPreservesOtherOwners() {
        launch("localResume"); completeOriginalFavoritesBeforeResumeCleanup()
        capture("Favorites removed; original reading positions still preserved", element: app.buttons["reader.recovery.localResume.begin"])
        prepareLocalResumeCleanup()
        let cancel = app.alerts["Fjern læsepositioner?"].buttons["Annuller"]
        capture("Cancel separate reading-position confirmation", element: cancel)
        cancel.tap()
        waitForAlertDismissal("Fjern læsepositioner?")
        wait("Cancellation consumes confirmation without writing resume data") {
            $0["resumeStatus"] as? String == "cancelled" && $0["resumeConfirmation"] as? Bool == false
        }
        XCTAssertEqual(report()["resumeOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 0)
        assertResumeOtherOwnersPreserved()
        prepareLocalResumeCleanup(); confirmLocalResumeCleanup()
        wait("Actual resume removal waits for its physical serial-store write") {
            $0["resumeStatus"] as? String == "removing" && $0["resumeWriteHeld"] as? Bool == true
        }
        XCTAssertEqual(report()["resumeOwnerCount"] as? Int, 2)
        XCTAssertFalse(app.staticTexts["reader.recovery.localResume.partial"].exists)
        capture("Reading-position cleanup awaits real storage acknowledgement", element: app.staticTexts["reader.recovery.localResume.status"])
        assertResumeOtherOwnersPreserved()
        tap("accountRecovery.releaseResume")
        wait("Readback confirms only the original account's anchors are removed") {
            $0["resumeStatus"] as? String == "removed" && $0["resumeOwnerCount"] as? Int == 0
        }
        capture("Reading positions removed; account deletion remains incomplete", element: app.staticTexts["reader.recovery.localResume.status"])
        capture("Remaining account cleanup stays explicit", element: app.staticTexts["reader.recovery.localResume.partial"])
        XCTAssertFalse(app.buttons["reader.recovery.localResume.begin"].exists)
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 1)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        assertResumeOtherOwnersPreserved()
        tap("accountRecovery.close"); open()
        wait("Reopening the same account content preserves the accepted local resume receipt") {
            $0["resumeStatus"] as? String == "removed"
        }
        assertResumeOtherOwnersPreserved()
    }

    func testFailedLocalResumeCleanupRetriesWithFreshConfirmation() {
        launch("localResumeFailure"); completeOriginalFavoritesBeforeResumeCleanup()
        prepareLocalResumeCleanup(); confirmLocalResumeCleanup()
        wait("The injected readback failure follows the actual held owner-removing write") {
            $0["resumeWriteHeld"] as? Bool == true
        }
        tap("accountRecovery.releaseResume")
        wait("Persisted removal without a successful readback cannot claim completion") {
            $0["resumeStatus"] as? String == "failed" && $0["resumeOwnerCount"] as? Int == 0
                && $0["resumeReadFailures"] as? Int == 1
        }
        XCTAssertEqual(report()["resumeConfirmation"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["reader.recovery.localResume.partial"].exists)
        capture("Readback failure leaves explicit local retry", element: app.staticTexts["reader.recovery.localResume.status"])
        assertResumeOtherOwnersPreserved()
        prepareLocalResumeCleanup()
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 1, "Preparing retry must not repeat the destructive write")
        confirmLocalResumeCleanup()
        wait("A fresh confirmation validates the persisted original-family result") {
            $0["resumeStatus"] as? String == "removed" && $0["resumeOwnerCount"] as? Int == 0
        }
        capture("Fresh retry confirms local reading-position cleanup only", element: app.staticTexts["reader.recovery.localResume.status"])
        XCTAssertEqual(report()["resumeWriteStarts"] as? Int, 1)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        assertResumeOtherOwnersPreserved()
    }

    private var podcastDisclosure: String {
        "Fjern denne kontos gemte lyttepositioner fra enheden. Andre kontis og gæstens positioner samt Research bevares. Downloadet lyd, downloadede artikler, iCloud og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført."
    }

    private func assertPodcastOtherOwnersPreserved() {
        XCTAssertEqual(report()["podcastOtherUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["podcastGuestUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["podcastLegacyUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["podcastPlaybackAccess"] as? Bool, false)
        assertResumeOtherOwnersPreserved()
    }

    private func completeOriginalResumeBeforePodcastCleanup() {
        completeOriginalFavoritesBeforeResumeCleanup()
        XCTAssertFalse(app.buttons["reader.recovery.localPodcast.begin"].exists)
        XCTAssertEqual(report()["podcastFactoryCalls"] as? Int, 0)
        XCTAssertEqual(report()["podcastReads"] as? Int, 0)
        XCTAssertEqual(report()["podcastOwnerCount"] as? Int, 2)
        prepareLocalResumeCleanup(); confirmLocalResumeCleanup()
        wait("Resume cleanup retains its actual asynchronous store boundary") { $0["resumeWriteHeld"] as? Bool == true }
        tap("accountRecovery.releaseResume")
        wait("Accepted resume receipt leaves podcast progress for a separate action") {
            $0["resumeStatus"] as? String == "removed" && $0["resumeOwnerCount"] as? Int == 0
        }
        XCTAssertEqual(report()["podcastFactoryCalls"] as? Int, 0, "The cleanup accessor must not construct raw storage")
        XCTAssertEqual(report()["podcastReads"] as? Int, 0)
        XCTAssertEqual(report()["podcastWrites"] as? Int, 0)
        XCTAssertEqual(report()["podcastOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["podcastStatus"] as? String, "idle")
        assertPodcastOtherOwnersPreserved()
    }

    private func prepareLocalPodcastCleanup() {
        tap("reader.recovery.localPodcast.begin")
        XCTAssertTrue(app.alerts["Fjern lyttepositioner?"].waitForExistence(timeout: 5))
        wait("The actual closed runtime prepares an original podcast snapshot for confirmation") {
            $0["podcastStatus"] as? String == "ready" && $0["podcastConfirmation"] as? Bool == true
        }
        captureLocalCleanupDisclosure(title: "Fjern lyttepositioner?", label: podcastDisclosure)
    }

    private func confirmLocalPodcastCleanup() {
        capture("Separate device-local listening-position confirmation", element: app.alerts["Fjern lyttepositioner?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        tap("reader.recovery.confirm")
        waitForAlertDismissal("Fjern lyttepositioner?")
    }

    func testLocalPodcastCleanupRequiresSeparateConfirmationAndPreservesOtherOwners() {
        launch("localPodcast"); completeOriginalResumeBeforePodcastCleanup()
        capture("Reading anchors removed; listening positions still preserved", element: app.buttons["reader.recovery.localPodcast.begin"])
        prepareLocalPodcastCleanup()
        XCTAssertEqual(report()["podcastWrites"] as? Int, 0, "Preparing a snapshot is not confirmation")
        let cancel = app.alerts["Fjern lyttepositioner?"].buttons["Annuller"]
        capture("Cancel separate listening-position confirmation", element: cancel)
        cancel.tap(); waitForAlertDismissal("Fjern lyttepositioner?")
        wait("Cancelling consumes the prepared confirmation without writing podcast data") {
            $0["podcastStatus"] as? String == "cancelled" && $0["podcastConfirmation"] as? Bool == false
        }
        XCTAssertEqual(report()["podcastOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["podcastWrites"] as? Int, 0)
        assertPodcastOtherOwnersPreserved()
        prepareLocalPodcastCleanup(); confirmLocalPodcastCleanup()
        wait("Actual synchronous storage and readback complete only the original owner's scope") {
            $0["podcastStatus"] as? String == "removed" && $0["podcastOwnerCount"] as? Int == 0
        }
        capture("Listening positions removed; account deletion remains incomplete", element: app.staticTexts["reader.recovery.localPodcast.status"])
        capture("Remaining work after listening-position cleanup stays explicit", element: app.staticTexts["reader.recovery.localPodcast.partial"])
        XCTAssertEqual(report()["podcastRemovalWrites"] as? Int, 1)
        XCTAssertFalse(app.buttons["reader.recovery.localPodcast.begin"].exists)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        assertPodcastOtherOwnersPreserved()
        tap("accountRecovery.close"); open()
        wait("The retained same flow preserves its local podcast receipt after reopening") {
            $0["podcastStatus"] as? String == "removed"
        }
        assertPodcastOtherOwnersPreserved()
    }

    func testFailedLocalPodcastCleanupRetriesWithFreshConfirmation() {
        launch("localPodcastFailure"); completeOriginalResumeBeforePodcastCleanup()
        prepareLocalPodcastCleanup(); confirmLocalPodcastCleanup()
        wait("Completed bytes with failed readback cannot claim local cleanup success") {
            $0["podcastStatus"] as? String == "failed" && $0["podcastOwnerCount"] as? Int == 0
                && $0["podcastReadFailures"] as? Int == 1
        }
        XCTAssertEqual(report()["podcastConfirmation"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["reader.recovery.localPodcast.partial"].exists)
        capture("Listening-position readback failure requires fresh confirmation", element: app.staticTexts["reader.recovery.localPodcast.status"])
        assertPodcastOtherOwnersPreserved()
        prepareLocalPodcastCleanup()
        XCTAssertEqual(report()["podcastRemovalWrites"] as? Int, 1)
        confirmLocalPodcastCleanup()
        wait("A freshly confirmed retry verifies the original completed record") {
            $0["podcastStatus"] as? String == "removed" && $0["podcastOwnerCount"] as? Int == 0
        }
        capture("Podcast retry confirms only local listening-position cleanup", element: app.staticTexts["reader.recovery.localPodcast.status"])
        XCTAssertEqual(report()["podcastRemovalWrites"] as? Int, 1)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        assertPodcastOtherOwnersPreserved()
    }

    private var introductionDisclosure: String {
        "Fjern denne kontos introduktionsudkast på enheden. En gennemført introduktion, andre kontis udkast, gæstevalg og Research bevares. Interesser gemt på kontoen, downloadet indhold, iCloud og øvrige kontodata er ikke omfattet. Kontosletningen er fortsat ikke gennemført."
    }

    private func assertIntroductionScopePreserved() {
        XCTAssertEqual(report()["introductionCompleted"] as? Bool, true)
        XCTAssertEqual(report()["introductionGuestUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["introductionAllowed"] as? Bool, false)
        XCTAssertEqual(report()["introductionPresented"] as? Bool, false)
        assertPodcastOtherOwnersPreserved()
    }

    private func completeOriginalPodcastBeforeIntroductionCleanup() {
        completeOriginalResumeBeforePodcastCleanup()
        XCTAssertFalse(app.buttons["reader.recovery.localIntroduction.begin"].exists)
        XCTAssertEqual(report()["introductionReads"] as? Int, 0)
        XCTAssertEqual(report()["introductionWrites"] as? Int, 0)
        XCTAssertEqual(report()["introductionCleanupWrites"] as? Int, 0)
        prepareLocalPodcastCleanup(); confirmLocalPodcastCleanup()
        wait("Podcast cleanup leaves the account's introduction draft for a separate action") {
            $0["podcastStatus"] as? String == "removed" && $0["podcastOwnerCount"] as? Int == 0
        }
        XCTAssertEqual(report()["introductionReads"] as? Int, 0)
        XCTAssertEqual(report()["introductionWrites"] as? Int, 0)
        XCTAssertEqual(report()["introductionCleanupReads"] as? Int, 0)
        XCTAssertEqual(report()["introductionCleanupWrites"] as? Int, 0)
        XCTAssertEqual(report()["introductionTopicCount"] as? Int, 2)
        XCTAssertEqual(report()["introductionReplaying"] as? Bool, true)
        XCTAssertEqual(report()["introductionOwnerCleared"] as? Bool, false)
        XCTAssertEqual(report()["introductionStatus"] as? String, "idle")
        assertIntroductionScopePreserved()
    }

    private func prepareLocalIntroductionCleanup() {
        tap("reader.recovery.localIntroduction.begin")
        XCTAssertTrue(app.alerts["Fjern introduktionsudkast?"].waitForExistence(timeout: 5))
        wait("The actual model prepares the original draft for a separate confirmation") {
            $0["introductionStatus"] as? String == "ready" && $0["introductionConfirmation"] as? Bool == true
        }
        captureLocalCleanupDisclosure(title: "Fjern introduktionsudkast?", label: introductionDisclosure)
    }

    private func confirmLocalIntroductionCleanup() {
        capture("Separate device-local introduction draft confirmation", element: app.alerts["Fjern introduktionsudkast?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        tap("reader.recovery.confirm")
        waitForAlertDismissal("Fjern introduktionsudkast?")
    }

    private func assertIntroductionDraftCleared() {
        XCTAssertEqual(report()["introductionTopicCount"] as? Int, 0)
        XCTAssertEqual(report()["introductionOwnerCleared"] as? Bool, true)
        XCTAssertEqual(report()["introductionStep"] as? String, "welcome")
        XCTAssertEqual(report()["introductionReplaying"] as? Bool, false)
        assertIntroductionScopePreserved()
    }

    func testLocalIntroductionCleanupRequiresSeparateConfirmationAndPreservesCompletedState() {
        launch("localIntroduction"); completeOriginalPodcastBeforeIntroductionCleanup()
        capture("Earlier local cleanup preserves the introduction draft", element: app.buttons["reader.recovery.localIntroduction.begin"])
        prepareLocalIntroductionCleanup()
        XCTAssertEqual(report()["introductionWrites"] as? Int, 0)
        XCTAssertEqual(report()["introductionCleanupWrites"] as? Int, 0)
        let cancel = app.alerts["Fjern introduktionsudkast?"].buttons["Annuller"]
        capture("Cancel separate introduction draft confirmation", element: cancel)
        cancel.tap(); waitForAlertDismissal("Fjern introduktionsudkast?")
        wait("Cancellation consumes the draft confirmation without source or metadata writes") {
            $0["introductionStatus"] as? String == "cancelled" && $0["introductionConfirmation"] as? Bool == false
        }
        XCTAssertEqual(report()["introductionTopicCount"] as? Int, 2)
        XCTAssertEqual(report()["introductionWrites"] as? Int, 0)
        XCTAssertEqual(report()["introductionCleanupWrites"] as? Int, 0)
        assertIntroductionScopePreserved()
        prepareLocalIntroductionCleanup(); confirmLocalIntroductionCleanup()
        wait("Source and sidecar readback confirm only the original introduction draft cleanup") {
            $0["introductionStatus"] as? String == "removed" && $0["introductionTopicCount"] as? Int == 0
        }
        assertIntroductionDraftCleared()
        capture("Draft removed without resetting completed introduction", element: app.staticTexts["reader.recovery.localIntroduction.status"])
        capture("Account cleanup remains incomplete after draft removal", element: app.staticTexts["reader.recovery.localIntroduction.partial"])
        XCTAssertEqual(report()["introductionClearWrites"] as? Int, 1)
        XCTAssertFalse(app.buttons["reader.recovery.localIntroduction.begin"].exists)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        tap("accountRecovery.close"); open()
        wait("Reopening the retained flow preserves the accepted introduction cleanup receipt") {
            $0["introductionStatus"] as? String == "removed"
        }
        assertIntroductionDraftCleared()
    }

    func testFailedLocalIntroductionCleanupRetriesWithFreshConfirmation() {
        launch("localIntroductionFailure"); completeOriginalPodcastBeforeIntroductionCleanup()
        prepareLocalIntroductionCleanup(); confirmLocalIntroductionCleanup()
        wait("A changed source with failed readback is not reported as completed cleanup") {
            $0["introductionStatus"] as? String == "failed" && $0["introductionTopicCount"] as? Int == 0
                && $0["introductionReadFailures"] as? Int == 1
        }
        XCTAssertEqual(report()["introductionConfirmation"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["reader.recovery.localIntroduction.partial"].exists)
        assertIntroductionDraftCleared()
        capture("Introduction readback failure requires a fresh confirmation", element: app.staticTexts["reader.recovery.localIntroduction.status"])
        prepareLocalIntroductionCleanup()
        XCTAssertEqual(report()["introductionClearWrites"] as? Int, 1)
        confirmLocalIntroductionCleanup()
        wait("A freshly confirmed retry completes original-family metadata after source readback") {
            $0["introductionStatus"] as? String == "removed" && $0["introductionTopicCount"] as? Int == 0
        }
        assertIntroductionDraftCleared()
        capture("Retry confirms the local introduction scope only", element: app.staticTexts["reader.recovery.localIntroduction.status"])
        XCTAssertEqual(report()["introductionClearWrites"] as? Int, 1)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
    }

    private var historyDisclosure: String {
        "Fjern denne kontos læsehistorik, der er tilgængelig på enheden. Andre kontis og gæstens historik samt Research bevares. Kontrollen bekræfter kun resultatet på denne enhed. Fjernelse fra iCloud og andre enheder er ikke bekræftet. Kontosletningen er fortsat ikke gennemført."
    }

    private func assertHistoryScopePreserved() {
        XCTAssertEqual(report()["historyOtherUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["historyGuestUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["historyLegacyUnchanged"] as? Bool, true)
        XCTAssertEqual(report()["historyCloudComplete"] as? Bool, false)
        XCTAssertEqual(report()["historyContextUnresolved"] as? Bool, true)
        XCTAssertEqual(report()["historyStaleEffectsDenied"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(report()["historyStaleProbes"] as? Int ?? 0, 1)
        XCTAssertGreaterThanOrEqual(report()["historyTimers"] as? Int ?? 0, 1)
        XCTAssertGreaterThanOrEqual(report()["historyObservers"] as? Int ?? 0, 1)
        XCTAssertEqual(report()["historyFactoryCalls"] as? Int, 1)
        XCTAssertEqual(report()["historySynchronizations"] as? Int, 1, "Only the injected normal preparation ran; cleanup does not synchronize")
        XCTAssertEqual(report()["historyProfileWrites"] as? Int, 0)
        assertIntroductionDraftCleared()
    }

    private func completeOriginalIntroductionBeforeHistoryCleanup() {
        let previous = capturePrerequisiteDisclosures
        capturePrerequisiteDisclosures = false
        defer { capturePrerequisiteDisclosures = previous }
        completeOriginalPodcastBeforeIntroductionCleanup()
        XCTAssertFalse(app.buttons["reader.recovery.localHistory.begin"].exists)
        XCTAssertEqual(report()["historyOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["historyReads"] as? Int, 0)
        XCTAssertEqual(report()["historyWrites"] as? Int, 0)
        prepareLocalIntroductionCleanup(); confirmLocalIntroductionCleanup()
        wait("The accepted introduction receipt leaves history for a separate confirmation") {
            $0["introductionStatus"] as? String == "removed" && $0["introductionTopicCount"] as? Int == 0
        }
        XCTAssertEqual(report()["historyStatus"] as? String, "idle")
        XCTAssertEqual(report()["historyOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["historyReads"] as? Int, 0)
        XCTAssertEqual(report()["historyWrites"] as? Int, 0)
        XCTAssertEqual(report()["historyMetadataReads"] as? Int, 0)
        XCTAssertEqual(report()["historyMetadataWrites"] as? Int, 0)
        assertHistoryScopePreserved()
    }

    private func prepareLocalHistoryCleanup() {
        tap("reader.recovery.localHistory.begin")
        XCTAssertTrue(app.alerts["Fjern lokal læsehistorik?"].waitForExistence(timeout: 5))
        wait("The original history snapshot has its own fresh confirmation") {
            $0["historyStatus"] as? String == "ready" && $0["historyConfirmation"] as? Bool == true
        }
        captureLocalCleanupDisclosure(title: "Fjern lokal læsehistorik?", label: historyDisclosure)
    }

    private func confirmLocalHistoryCleanup() {
        capture("Separate local reading-history confirmation", element: app.alerts["Fjern lokal læsehistorik?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        tap("reader.recovery.confirm")
        waitForAlertDismissal("Fjern lokal læsehistorik?")
    }

    func testLocalHistoryCleanupRequiresSeparateConfirmationAndKeepsCloudPending() {
        launch("localHistory"); completeOriginalIntroductionBeforeHistoryCleanup()
        capture("Earlier cleanup leaves reading history for its own action", element: app.buttons["reader.recovery.localHistory.begin"])
        prepareLocalHistoryCleanup()
        XCTAssertEqual(report()["historyWrites"] as? Int, 0)
        XCTAssertEqual(report()["historyMetadataWrites"] as? Int, 0)
        let cancel = app.alerts["Fjern lokal læsehistorik?"].buttons["Annuller"]
        capture("Cancel separate local reading-history confirmation", element: cancel)
        cancel.tap(); waitForAlertDismissal("Fjern lokal læsehistorik?")
        wait("Cancellation consumes the snapshot without changing history or metadata") {
            $0["historyStatus"] as? String == "cancelled" && $0["historyConfirmation"] as? Bool == false
        }
        XCTAssertEqual(report()["historyOwnerCount"] as? Int, 2)
        XCTAssertEqual(report()["historyWrites"] as? Int, 0)
        XCTAssertEqual(report()["historyMetadataWrites"] as? Int, 0)
        assertHistoryScopePreserved()
        prepareLocalHistoryCleanup(); confirmLocalHistoryCleanup()
        wait("Local source and sidecar readback do not claim iCloud completion") {
            $0["historyStatus"] as? String == "removed" && $0["historyOwnerCount"] as? Int == 0
                && $0["historyLocalReadback"] as? Bool == true && ($0["historyStaleProbes"] as? Int ?? 0) >= 2
        }
        XCTAssertEqual(report()["historyRemovalWrites"] as? Int, 1)
        assertHistoryScopePreserved()
        capture("Local history readback confirmed with cloud still pending", element: app.staticTexts["reader.recovery.localHistory.status"])
        capture("iCloud and complete account deletion remain unconfirmed", element: app.staticTexts["reader.recovery.localHistory.partial"])
        XCTAssertFalse(app.buttons["reader.recovery.localHistory.begin"].exists)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        tap("accountRecovery.close"); open()
        wait("The retained same-flow history receipt remains local only after reopening") {
            $0["historyStatus"] as? String == "removed" && $0["historyLocalReadback"] as? Bool == true
        }
        assertHistoryScopePreserved()
    }

    func testFailedLocalHistoryCleanupRetriesWithoutClaimingCloudRemoval() {
        launch("localHistoryFailure"); completeOriginalIntroductionBeforeHistoryCleanup()
        prepareLocalHistoryCleanup(); confirmLocalHistoryCleanup()
        wait("Persisted empty history with failed readback is not a successful receipt") {
            $0["historyStatus"] as? String == "failed" && $0["historyOwnerCount"] as? Int == 0
                && $0["historyReadFailures"] as? Int == 1 && ($0["historyStaleProbes"] as? Int ?? 0) >= 2
        }
        XCTAssertEqual(report()["historyConfirmation"] as? Bool, false)
        XCTAssertEqual(report()["historyLocalReadback"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["reader.recovery.localHistory.partial"].exists)
        assertHistoryScopePreserved()
        capture("History readback failure requires a fresh local confirmation", element: app.staticTexts["reader.recovery.localHistory.status"])
        prepareLocalHistoryCleanup()
        XCTAssertEqual(report()["historyRemovalWrites"] as? Int, 1)
        confirmLocalHistoryCleanup()
        wait("Fresh confirmation validates only the original local history result") {
            $0["historyStatus"] as? String == "removed" && $0["historyLocalReadback"] as? Bool == true
        }
        XCTAssertEqual(report()["historyRemovalWrites"] as? Int, 1)
        XCTAssertEqual(report()["historyOwnerCount"] as? Int, 0)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        assertHistoryScopePreserved()
        capture("Retry confirms local history readback, not iCloud removal", element: app.staticTexts["reader.recovery.localHistory.status"])
        capture("Cloud work stays explicit after local retry", element: app.staticTexts["reader.recovery.localHistory.partial"])
    }

    private let pushDisclosure = "Luk push for denne kontos bekræftede installation. Denne installation kan ikke tilmeldes push igen bagefter. Du skal bekræfte din identitet igen. Andre enheder og Research bevares. Allerede afsendte eller igangsatte beskeder kan ikke tilbagekaldes. Historiske pushdata og øvrige kontodata er ikke omfattet. Hele kontosletningen er fortsat uafsluttet."
    private let pushRetryDisclosure = "Prøv den samme anmodning igen med ny bekræftelse af din identitet. Et tidligere forsøg kan allerede være gennemført. Vi bruger den oprindelige installation og samme bekræftede oplysninger. Ingen ny installation vælges. Hele kontosletningen er fortsat uafsluttet."

    private func prepareOriginalPushInstallation() {
        tap("reader.recovery.push.begin")
        XCTAssertTrue(app.secureTextFields["account.password"].waitForExistence(timeout: 5))
        passwordAndSubmit()
        XCTAssertEqual(report()["pushStatus"] as? String, "preparing")
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 0)
        tap("accountRecovery.releaseHTTP")
        wait("Actual HTTP preparation yields only a separate original confirmation") {
            $0["pushStatus"] as? String == "ready" && $0["pushConfirmation"] as? Bool == true
                && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertTrue(app.alerts["Luk push for denne installation?"].waitForExistence(timeout: 5))
        captureLocalCleanupDisclosure(title: "Luk push for denne installation?", label: pushDisclosure)
        if capturePrerequisiteDisclosures {
            capture("Push retirement requires the separate fully visible action", element: app.alerts["Luk push for denne installation?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 0)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        assertLocalOtherOwnersPreserved()
    }

    private func assertScopedPushOutcome() {
        XCTAssertEqual(report()["status"] as? String, "ledgerDataRemoved")
        XCTAssertEqual(report()["pushReceipt"] as? Bool, true)
        XCTAssertEqual(report()["complete"] as? Bool, false)
        XCTAssertEqual(report()["pushHistoricalComplete"] as? Bool, false)
        XCTAssertEqual(report()["pushDeliveriesRecalled"] as? Bool, false)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        XCTAssertEqual(report()["localJournalFactoryCalls"] as? Int, 0)
        XCTAssertEqual(report()["localRemoveStarts"] as? Int, 0)
        XCTAssertEqual(report()["ownV1"] as? Bool, true)
        XCTAssertEqual(report()["ownV2"] as? Bool, true)
        let actions = report()["actionIDs"] as? [String] ?? []
        XCTAssertEqual(Set(actions).count, actions.count, "Every wire phase uses a fresh original identity action")
        assertLocalOtherOwnersPreserved()
    }

    func testPushInstallationRequiresSeparateConfirmationAndFreshIdentity() {
        launch("pushInstallation"); completeOriginalCloudPhasesForLocalCleanup()
        XCTAssertEqual(report()["pushVaultReads"] as? Int, 0, "Rendering and parent phases must not discover the installation")
        capture("Explicit push preparation after accepted original parent and ledger", element: app.buttons["reader.recovery.push.begin"])
        prepareOriginalPushInstallation()
        tap("Annuller")
        waitForAlertDismissal("Luk push for denne installation?")
        wait("Cancelling preparation retires its confirmation without sending a commit") {
            $0["pushStatus"] as? String == "cancelled" && $0["pushConfirmation"] as? Bool == false
        }
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 0)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        prepareOriginalPushInstallation()
        confirm(); passwordAndSubmit()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 5)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 2)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushStatus"] as? String, "retiring")
        capture("Fresh identity and held commit remain visibly pending", element: app.staticTexts["reader.recovery.push.status"])
        tap("accountRecovery.releaseHTTP")
        wait("Only the valid original HTTP commit receipt closes this installation") {
            $0["pushStatus"] as? String == "retired" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 1)
        assertScopedPushOutcome()
        capture("Scoped installation retirement with remaining work explicit", element: app.staticTexts["reader.recovery.push.status"])
        capture("Other devices and whole account remain outside this result", element: app.staticTexts["reader.recovery.push.partial"])
        XCTAssertFalse(app.buttons["reader.recovery.push.begin"].exists)
        XCTAssertFalse(app.buttons["reader.recovery.push.retry"].exists)
    }

    func testMissingPushAcknowledgmentStartsNoProviderOrRequest() {
        launch("pushMissingACK"); completeOriginalCloudPhasesForLocalCleanup()
        XCTAssertEqual(report()["pushVaultReads"] as? Int, 0)
        XCTAssertEqual(report()["pushVaultHasACK"] as? Bool, false)
        tap("reader.recovery.push.begin")
        wait("A legacy record without acknowledged ownership is unavailable, never relabeled") {
            $0["pushStatus"] as? String == "unavailable" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 2)
        XCTAssertEqual(report()["httpCalls"] as? Int, 2)
        XCTAssertEqual(report()["pushVaultReads"] as? Int, 1)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        XCTAssertEqual(report()["pushVaultRevision"] as? Int, 17)
        XCTAssertEqual(report()["pushVaultHasACK"] as? Bool, false)
        XCTAssertFalse(app.secureTextFields["account.password"].exists)
        XCTAssertFalse(app.alerts["Luk push for denne installation?"].exists)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        assertLocalOtherOwnersPreserved()
        capture("Missing acknowledged installation remains honestly unavailable", element: app.staticTexts["reader.recovery.push.status"])
    }

    func testChangedPushBindingRejectsCommitWithoutAdoptingReplacement() {
        launch("pushChangedBinding"); completeOriginalCloudPhasesForLocalCleanup()
        prepareOriginalPushInstallation()
        confirm(); passwordAndSubmit(expectHeldHTTP: false)
        XCTAssertEqual(report()["pushStatus"] as? String, "unavailable")
        XCTAssertEqual(report()["sdkCalls"] as? Int, 4)
        XCTAssertEqual(report()["httpCalls"] as? Int, 3)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 0)
        XCTAssertEqual(report()["pushVaultOwner"] as? String, "local-reader-B")
        XCTAssertEqual(report()["pushVaultRevision"] as? Int, 18)
        XCTAssertEqual(report()["pushVaultReplacements"] as? Int, 1)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        XCTAssertEqual(report()["pushCanPrepare"] as? Bool, false)
        XCTAssertFalse(app.buttons["reader.recovery.push.begin"].exists)
        assertLocalOtherOwnersPreserved()
        capture("Replacement account binding is preserved and never adopted", element: app.staticTexts["reader.recovery.push.status"])
    }

    func testTimedOutPushCommitKeepsPhysicalFlightAndRetriesExactSnapshot() {
        launch("pushTimeout"); completeOriginalCloudPhasesForLocalCleanup()
        prepareOriginalPushInstallation()
        confirm(); passwordAndSubmit()
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 1)
        tap("accountRecovery.pushTimeout")
        wait("Timeout closes observation while the physical injected request is still held") {
            $0["pushStatus"] as? String == "timedOut" && $0["httpHeld"] as? Bool == true
                && $0["physicalFlight"] as? Bool == true
        }
        XCTAssertEqual(report()["pushCanPrepare"] as? Bool, false)
        XCTAssertEqual(report()["pushCanRetry"] as? Bool, false)
        XCTAssertFalse(app.buttons["reader.recovery.push.retry"].exists)
        capture("Timed-out observation retains the actual physical request", element: app.staticTexts["reader.recovery.push.status"])
        tap("accountRecovery.releaseHTTP")
        wait("Late committed local response releases the slot but cannot publish current success") {
            $0["pushStatus"] as? String == "timedOut" && $0["physicalFlight"] as? Bool == false
                && $0["pushCanRetry"] as? Bool == true
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 1)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        tap("reader.recovery.push.retry")
        XCTAssertTrue(app.alerts["Prøv samme anmodning igen?"].waitForExistence(timeout: 5))
        captureLocalCleanupDisclosure(title: "Prøv samme anmodning igen?", label: pushRetryDisclosure)
        capture("Exact retry is separately confirmed before a fresh identity form", element: app.alerts["Prøv samme anmodning igen?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        confirm(); passwordAndSubmit()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 5)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1, "An uncertain commit must not regenerate its snapshot")
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 2)
        let digests = report()["pushCommitDigests"] as? [String] ?? []
        XCTAssertEqual(digests.count, 2)
        XCTAssertEqual(Set(digests).count, 1, "Both physical requests preserve exact original request bytes")
        tap("accountRecovery.releaseHTTP")
        wait("Fresh exact retry accepts the historical scoped response") {
            $0["pushStatus"] as? String == "retired" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 1)
        assertScopedPushOutcome()
        capture("Retry closes only the original installation", element: app.staticTexts["reader.recovery.push.status"])
        capture("No recalled deliveries or full deletion claim after retry", element: app.staticTexts["reader.recovery.push.partial"])
    }

    /// Execute the actual original commit before replacing the fixture. The
    /// simulated remote result survives, but the timed-out observer accepts
    /// no receipt. Rebuilding objects is not an operating-system restart.
    private func reconstructAfterAmbiguousPushCommit(_ scenario: String) {
        launch(scenario)
        capturePrerequisiteDisclosures = false
        completeOriginalCloudPhasesForLocalCleanup()
        prepareOriginalPushInstallation()
        confirm(); passwordAndSubmit()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 4)
        XCTAssertEqual(report()["httpCalls"] as? Int, 4)
        tap("accountRecovery.pushTimeout")
        wait("Original commit times out while the physical local transport is held") {
            $0["pushStatus"] as? String == "timedOut" && $0["httpHeld"] as? Bool == true
                && $0["physicalFlight"] as? Bool == true
        }
        XCTAssertEqual(report()["pushCanReconstruct"] as? Bool, false)
        XCTAssertEqual(report()["pushCanRetry"] as? Bool, false)
        tap("accountRecovery.releaseHTTP")
        wait("A late original response does not publish a current receipt") {
            $0["pushStatus"] as? String == "timedOut" && $0["physicalFlight"] as? Bool == false
                && $0["pushCanReconstruct"] as? Bool == true
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 1)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        XCTAssertEqual(report()["pushStoredCommit"] as? Bool, true)
        let originalFlow = report()["flowID"] as? String
        XCTAssertFalse(originalFlow?.isEmpty ?? true)
        let vaultReads = report()["pushVaultReads"] as? Int
        let originalIDs = report()["sentIDs"] as? [String] ?? []
        tap("accountRecovery.reconstruct")
        wait("Fresh Auth/startup/recovery objects bootstrap retained isolated file bytes") {
            $0["pushReconstructionCount"] as? Int == 1 && $0["ready"] as? Bool == true
                && $0["flowID"] as? String == ""
        }
        assertClosedReader()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 4)
        XCTAssertEqual(report()["httpCalls"] as? Int, 4)
        XCTAssertEqual(report()["pushVaultReads"] as? Int, vaultReads, "Reconstruction/rendering cannot inspect or replace the installation")
        completeOriginalCloudPhasesForLocalCleanup(expectedHTTPCalls: 6, expectedSDKCalls: 6)
        XCTAssertNotEqual(report()["flowID"] as? String, originalFlow, "The actual coordinator and prompt family must be newly constructed")
        XCTAssertEqual(report()["pushStatus"] as? String, "idle")
        XCTAssertEqual(report()["pushStoredCommit"] as? Bool, true)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        XCTAssertEqual(report()["pushVaultReads"] as? Int, vaultReads, "Fresh parent/ledger reconciliation does not silently read the vault")
        let reconciledIDs = report()["sentIDs"] as? [String] ?? []
        XCTAssertEqual(reconciledIDs.count, 6)
        XCTAssertEqual(Array(reconciledIDs.suffix(2)), Array(originalIDs.prefix(2)), "Reconciliation preserves the original parent/ledger family")
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        capturePrerequisiteDisclosures = true
    }

    func testReconstructedPushCommitRequiresFreshExactRetry() {
        reconstructAfterAmbiguousPushCommit("pushRestart")
        let begin = app.buttons["reader.recovery.push.begin"]
        capture("Retained original push request is resumed explicitly after reconciliation", element: begin)
        XCTAssertEqual(begin.label, "Genoptag tidligere pushoprydning")
        let sdkCalls = report()["sdkCalls"] as? Int, httpCalls = report()["httpCalls"] as? Int
        tap("reader.recovery.push.begin")
        wait("Local restoration validates the original ACK without provider or prepare transport") {
            $0["pushStatus"] as? String == "awaitingRetry" && $0["pushCanRetry"] as? Bool == true
                && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, sdkCalls)
        XCTAssertEqual(report()["httpCalls"] as? Int, httpCalls)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        XCTAssertFalse(app.secureTextFields["account.password"].exists)
        XCTAssertFalse(app.alerts["Luk push for denne installation?"].exists)
        tap("reader.recovery.push.retry")
        XCTAssertTrue(app.alerts["Prøv samme anmodning igen?"].waitForExistence(timeout: 5))
        captureLocalCleanupDisclosure(title: "Prøv samme anmodning igen?", label: pushRetryDisclosure)
        capture("Reconstructed exact retry requires its own fully visible confirmation", element: app.alerts["Prøv samme anmodning igen?"].buttons.matching(identifier: "reader.recovery.confirm").firstMatch)
        confirm(); passwordAndSubmit()
        XCTAssertEqual(report()["sdkCalls"] as? Int, 7)
        XCTAssertEqual(report()["httpCalls"] as? Int, 7)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 2)
        let ids = report()["pushCommitIDs"] as? [String] ?? []
        let digests = report()["pushCommitDigests"] as? [String] ?? []
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(Set(ids).count, 1)
        XCTAssertEqual(digests.count, 2); XCTAssertEqual(Set(digests).count, 1)
        tap("accountRecovery.releaseHTTP")
        wait("Fresh proof accepts only the original scoped result after object reconstruction") {
            $0["pushStatus"] as? String == "retired" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["pushRemoteCommits"] as? Int, 1)
        assertScopedPushOutcome()
        capture("Reconstructed retry confirms only this installation", element: app.staticTexts["reader.recovery.push.status"])
        capture("Reconstructed result leaves whole-account deletion unfinished", element: app.staticTexts["reader.recovery.push.partial"])
    }

    func testReconstructedPushCommitRejectsReplacementBeforeProvider() {
        reconstructAfterAmbiguousPushCommit("pushRestartChangedACK")
        XCTAssertEqual(report()["pushVaultOwner"] as? String, "local-reader-B")
        XCTAssertEqual(report()["pushVaultRevision"] as? Int, 18)
        XCTAssertEqual(report()["pushVaultReplacements"] as? Int, 1)
        tap("reader.recovery.push.begin")
        wait("The retained original request cannot adopt a replacement installation ACK") {
            $0["pushStatus"] as? String == "unavailable" && $0["physicalFlight"] as? Bool == false
        }
        XCTAssertEqual(report()["sdkCalls"] as? Int, 6)
        XCTAssertEqual(report()["httpCalls"] as? Int, 6)
        XCTAssertEqual(report()["pushPreparationCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushCommitCalls"] as? Int, 1)
        XCTAssertEqual(report()["pushReceipt"] as? Bool, false)
        XCTAssertEqual(report()["pushVaultWrites"] as? Int, 0)
        XCTAssertEqual(report()["pushVaultOwner"] as? String, "local-reader-B")
        XCTAssertEqual(report()["pushVaultRevision"] as? Int, 18)
        XCTAssertEqual(report()["pushCanRetry"] as? Bool, false)
        XCTAssertFalse(app.secureTextFields["account.password"].exists)
        XCTAssertFalse(app.alerts["Prøv samme anmodning igen?"].exists)
        assertLocalOtherOwnersPreserved()
        capture("Replacement ACK remains unavailable without a new identity action or request", element: app.staticTexts["reader.recovery.push.status"])
    }

}
