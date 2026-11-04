import XCTest

/// Actual settings card and injected OfflineManager/coordinator. Physical probes
/// and body fetches are held in memory. The audio scenarios use the actual local
/// cache, complete temporary artifacts and verified receipts; no media is played.
final class OfflineSettingsSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposOfflineSettingsSmoke", "-OfflineSettingsScenario", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["offlineSettings.fixture.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["offlineSettings.fixture.firebase"].label, "Firebase: ikke startet")
        XCTAssertEqual(report()["firebaseStarted"] as? Bool, false)
    }
    private func report() -> [String: Any] {
        guard let value = app.staticTexts["offlineSettings.fixture.report"].value as? String,
              let bytes = value.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
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
    private func fullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let controls = app.otherElements["offlineSettings.fixture.controls"]
        let isProduct = (element.identifier.hasPrefix("offlineSettings.") && !element.identifier.hasPrefix("offlineSettings.fixture."))
            || element.identifier.hasPrefix("offline.body.")
        let bottom = isProduct && controls.exists ? min(app.frame.maxY, controls.frame.minY) : app.frame.maxY
        let scroll = app.scrollViews["offlineSettings.fixture.scroll"]
        let navigation = app.navigationBars.firstMatch
        let navigationBottom = navigation.exists ? navigation.frame.maxY : app.frame.minY
        let top = isProduct && scroll.exists ? max(navigationBottom, scroll.frame.minY) : app.frame.minY
        return element.frame.minX >= app.frame.minX && element.frame.maxX <= app.frame.maxX
            && element.frame.minY >= top && element.frame.maxY <= bottom
    }
    private func expose(_ elements: [XCUIElement]) {
        let scroll = app.scrollViews["offlineSettings.fixture.scroll"]
        for _ in 0..<16 {
            if elements.allSatisfy({ fullyVisible($0) }) { return }
            guard scroll.exists else { break }
            let target = elements.first(where: { !fullyVisible($0) })
            let navigation = app.navigationBars.firstMatch
            let top = max(scroll.frame.minY, navigation.exists ? navigation.frame.maxY : app.frame.minY) + 8
            let controls = app.otherElements["offlineSettings.fixture.controls"]
            let bottom = min(scroll.frame.maxY, controls.exists ? controls.frame.minY : app.frame.maxY) - 8
            guard bottom > top else { break }
            // Short, measured drags avoid oscillating past a target at AX5.
            let above = target?.exists == true && target!.frame.minY < top
            let distance = min(120, max(30, above ? top - target!.frame.minY : (target?.frame.maxY ?? bottom) - bottom))
            let center = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: scroll.frame.midX, dy: center))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: scroll.frame.midX, dy: center + (above ? distance : -distance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
    private func tap(_ id: String) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 5), id); expose([element])
        XCTAssertTrue(fullyVisible(element), id); XCTAssertTrue(element.isEnabled, id); element.tap()
    }
    private func capture(_ name: String, required: [XCUIElement]) {
        expose(required); required.forEach { XCTAssertTrue(fullyVisible($0), $0.identifier) }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let state = XCTAttachment(string: String(describing: report()))
        state.name = name + " — actual manager counters/system text"; state.lifetime = .keepAlways; add(state)
    }
    private func seed(_ count: Int) {
        tap("offlineSettings.fixture.seed")
        wait("Original collection is loaded and bounded physical probes start") {
            $0["loaded"] as? Bool == true && $0["total"] as? Int == count
                && $0["heldProbes"] as? Int == min(count, 4)
        }
        XCTAssertEqual(report()["available"] as? Int, 0)
        XCTAssertLessThanOrEqual(report()["maximumHeld"] as? Int ?? 99, 4)
    }
    private func drainProbes() {
        for _ in 0..<8 {
            if report()["checking"] as? Int == 0 { break }
            wait("A bounded probe batch is available for explicit local completion") { ($0["heldProbes"] as? Int ?? 0) > 0 }
            tap("offlineSettings.fixture.releaseProbes")
        }
        wait("Every member is classified after physical probe completion") { $0["checking"] as? Int == 0 && $0["heldProbes"] as? Int == 0 }
    }
    private func redrawWithoutIO(_ times: Int = 4) {
        let before = report()
        for offset in 1...times {
            tap("offlineSettings.fixture.redraw")
            wait("Observed connectivity redraw completes without restarting the collection") {
                $0["redraws"] as? Int == (before["redraws"] as? Int ?? 0) + offset
            }
        }
        for key in ["probes", "indexReads", "bodyReads", "writes"] {
            XCTAssertEqual(report()[key] as? Int, before[key] as? Int, "Render-only changes must not alter \(key)")
        }
    }

    func testWholeLibraryExceedingProbeCapacityHasHonestUnknownFailureRetryAndMemoryOnlyRedraw() {
        launch("library")
        XCTAssertTrue(app.staticTexts["offlineSettings.unknown"].exists)
        XCTAssertFalse(app.staticTexts["offlineSettings.available"].exists)
        XCTAssertEqual(report()["loaded"] as? Bool, false); XCTAssertEqual(report()["probes"] as? Int, 0)
        capture("Offline settings — unresolved collection is unknown, not zero available",
                required: [app.staticTexts["offlineSettings.unknown"]])
        seed(9)
        XCTAssertEqual(report()["checking"] as? Int, 9)
        capture("Offline settings — nine members wait behind four physical probes",
                required: [app.staticTexts["offlineSettings.available"], app.staticTexts["offlineSettings.checking"]])
        redrawWithoutIO(); drainProbes()
        XCTAssertEqual(report()["probes"] as? Int, 9)
        XCTAssertEqual(report()["available"] as? Int, 8); XCTAssertEqual(report()["checkFailed"] as? Int, 1)
        XCTAssertEqual(report()["notDownloaded"] as? Int, 0)
        XCTAssertEqual(app.staticTexts["offlineSettings.available"].label, "Artikeltekst klar offline: 8 af 9")
        XCTAssertEqual(app.staticTexts["offlineSettings.checkFailed"].label, "Status kunne ikke kontrolleres: 1")
        XCTAssertGreaterThanOrEqual(app.buttons["offlineSettings.retry"].frame.height, 44)
        capture("Offline settings — a failed control is separate from missing text",
                required: [app.staticTexts["offlineSettings.checkFailed"], app.buttons["offlineSettings.retry"]])
        redrawWithoutIO(); tap("offlineSettings.retry")
        wait("Explicit status retry starts bounded checks without writes or body downloads") { $0["heldProbes"] as? Int == 4 }
        drainProbes()
        XCTAssertEqual(report()["available"] as? Int, 9); XCTAssertEqual(report()["checkFailed"] as? Int, 0)
        XCTAssertEqual(report()["probes"] as? Int, 18)
        XCTAssertEqual(report()["writes"] as? Int, 0); XCTAssertEqual(report()["bodyReads"] as? Int, 0)
        XCTAssertEqual(report()["indexReads"] as? Int, 0)
        XCTAssertEqual(app.staticTexts["offlineSettings.available"].label, "Artikeltekst klar offline: 9 af 9")
        capture("Offline settings — all article texts confirmed after explicit retry",
                required: [app.staticTexts["offlineSettings.available"]])
        let scope = app.staticTexts["offlineSettings.scope"]
        XCTAssertTrue(scope.label.contains("Tekst og lyd skal være hentet"))
        XCTAssertTrue(scope.label.contains("Billeder kan kræve netværk"))
        capture("Offline settings — visible scope requires actual text and audio", required: [scope])
        redrawWithoutIO()
        tap("offlineSettings.fixture.toggle")
        XCTAssertTrue(app.staticTexts["offlineSettings.fixture.hidden"].waitForExistence(timeout: 5))
        tap("offlineSettings.fixture.evict")
        let beforeReopen = report()["probes"] as? Int ?? 0
        tap("offlineSettings.fixture.toggle")
        wait("Appearance revalidates previously available text after hidden eviction") {
            $0["probes"] as? Int == beforeReopen + 4 && $0["heldProbes"] as? Int == 4
                && $0["available"] as? Int == 0 && $0["checking"] as? Int == 9
        }
        drainProbes()
        XCTAssertEqual(report()["available"] as? Int, 0); XCTAssertEqual(report()["notDownloaded"] as? Int, 9)
        capture("Offline settings — reopening checks evicted bytes before claiming availability",
                required: [app.staticTexts["offlineSettings.available"], app.staticTexts["offlineSettings.notDownloaded"]])
        redrawWithoutIO()
    }

    func testPendingDownloadFailedWriteAndConfirmedSaveStayDistinctUntilPhysicalCompletion() {
        launch("mixed"); seed(3); drainProbes()
        XCTAssertEqual(report()["notDownloaded"] as? Int, 3)
        tap("offlineSettings.fixture.startWrites")
        wait("Actual pending fetch, failed save and stored text are shown separately") {
            $0["pending"] as? Int == 1 && $0["failed"] as? Int == 1 && $0["available"] as? Int == 1
        }
        XCTAssertEqual(report()["favoriteCount"] as? Int, 3)
        XCTAssertEqual(app.staticTexts["offlineSettings.available"].label, "Artikeltekst klar offline: 1 af 3")
        XCTAssertEqual(app.staticTexts["offlineSettings.pending"].label, "Henter artikeltekst: 1")
        XCTAssertEqual(app.staticTexts["offlineSettings.failed"].label, "Artikeltekst kunne ikke gemmes: 1")
        capture("Offline settings — available text and pending download",
                required: [app.staticTexts["offlineSettings.available"], app.staticTexts["offlineSettings.pending"]])
        capture("Offline settings — failed storage remains separate from pending download",
                required: [app.staticTexts["offlineSettings.failed"]])
        redrawWithoutIO()
        tap("offlineSettings.fixture.releaseFetch")
        wait("The pending download counts only after the actual save succeeds") {
            $0["available"] as? Int == 2 && $0["pending"] as? Int == 0 && $0["failed"] as? Int == 1
        }
        tap("offlineSettings.fixture.retry")
        wait("Explicit existing body retry is pending, not available") { $0["pending"] as? Int == 1 && $0["available"] as? Int == 2 }
        tap("offlineSettings.fixture.releaseFetch")
        wait("All three article texts are stored without changing favorite membership") {
            $0["available"] as? Int == 3 && $0["failed"] as? Int == 0 && $0["pending"] as? Int == 0
                && $0["favoriteCount"] as? Int == 3
        }
        capture("Offline settings — confirmed saved texts after local retry",
                required: [app.staticTexts["offlineSettings.available"]])
        redrawWithoutIO()
    }

    func testAccountRoundTripRejectsOldProbeResultsAndDisappearanceCancelsOnlyOriginalRefresh() {
        launch("account"); seed(9)
        let oldGeneration = report()["generation"] as? String
        tap("offlineSettings.fixture.roundTrip")
        wait("The current A collection has a new original generation") {
            $0["generationChanged"] as? Bool == true && $0["generation"] as? String != oldGeneration
                && $0["available"] as? Int == 0 && $0["checking"] as? Int == 9
        }
        tap("offlineSettings.fixture.releaseProbes")
        wait("Old true results free physical slots but cannot mark new A available") {
            $0["probes"] as? Int == 8 && $0["heldProbes"] as? Int == 4 && $0["available"] as? Int == 0
        }
        capture("Offline settings — old A callbacks cannot restore availability in new A",
                required: [app.staticTexts["offlineSettings.available"], app.staticTexts["offlineSettings.checking"]])
        tap("offlineSettings.fixture.toggle")
        XCTAssertTrue(app.staticTexts["offlineSettings.fixture.hidden"].waitForExistence(timeout: 5))
        tap("offlineSettings.fixture.releaseProbes")
        wait("Original refresh teardown waits for physical callbacks without dispatching remaining members") { $0["heldProbes"] as? Int == 0 }
        let stopped = report()["probes"] as? Int
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.report()["probes"] as? Int != stopped
        }, object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 1), .completed)
        tap("offlineSettings.fixture.toggle")
        wait("A fresh visible refresh resumes the remaining original members") { ($0["heldProbes"] as? Int ?? 0) > 0 }
        drainProbes()
        XCTAssertEqual(report()["available"] as? Int, 0); XCTAssertEqual(report()["notDownloaded"] as? Int, 9)
        XCTAssertEqual(report()["favoriteCount"] as? Int, 9)
        XCTAssertEqual(report()["indexReads"] as? Int, 0); XCTAssertEqual(report()["bodyReads"] as? Int, 0)
        XCTAssertLessThanOrEqual(report()["maximumHeld"] as? Int ?? 99, 4)
        capture("Offline settings — new account generation has no confirmed stored text",
                required: [app.staticTexts["offlineSettings.available"], app.staticTexts["offlineSettings.notDownloaded"]])
        redrawWithoutIO()
    }

    func testAutomaticSavedArticleIsReadyOnlyAfterActualAudioReceiptAndKeepsItOffline() {
        launch("audio")
        tap("offlineSettings.fixture.seed")
        wait("An ordinary local save stores text and automatically starts one held audio transport") {
            $0["available"] as? Int == 1 && $0["audioStarts"] as? Int == 1
                && $0["heldAudio"] as? Int == 1 && $0["audioState"] as? String == "downloading"
                && $0["combinedReady"] as? Int == 0 && $0["combinedTotal"] as? Int == 1
        }
        let before = report()
        XCTAssertEqual(before["actualLocalAudioCache"] as? Bool, true)
        XCTAssertEqual(before["bodyStorageIsMemory"] as? Bool, true)
        XCTAssertEqual(before["writes"] as? Int, 1)
        XCTAssertEqual(before["audioSavedEvents"] as? Int, 0)
        XCTAssertEqual(before["audioDownloadedForMember"] as? Bool, false)
        XCTAssertEqual(before["audioFileURL"] as? Bool, false)
        XCTAssertEqual(app.staticTexts["offlineSettings.available"].label, "Artikeltekst klar offline: 1 af 1")
        XCTAssertEqual(app.staticTexts["offlineSettings.complete"].label, "Tekst og lyd klar offline: 0 af 1")
        captureAudio("Automatic offline — text is present while real audio is held; combined status is not ready",
            required: [app.staticTexts["offlineSettings.complete"]])
        let bodyStatus = app.staticTexts["offline.body.status"]
        XCTAssertTrue(bodyStatus.exists)
        XCTAssertEqual(bodyStatus.label, "Henter lyd…", "The shared article status cannot claim full readiness from text alone")
        captureAudio("Automatic offline — actual shared article control waits for audio", required: [bodyStatus])
        tap("offlineSettings.fixture.releaseAudio")
        wait("The actual cache commits its complete artifact and exact receipt before combined ready") {
            $0["combinedReady"] as? Int == 1 && $0["combinedAudioAvailable"] as? Int == 1
                && $0["audioState"] as? String == "available" && $0["audioSavedEvents"] as? Int == 1
                && $0["heldAudio"] as? Int == 0 && $0["audioDownloadedForMember"] as? Bool == true
                && $0["audioFileURL"] as? Bool == true
        }
        XCTAssertEqual(report()["fixtureID"] as? String, before["fixtureID"] as? String)
        XCTAssertEqual(report()["audioAccessLease"] as? String, before["audioAccessLease"] as? String)
        XCTAssertEqual(report()["audioAccessRevision"] as? String, report()["audioRevision"] as? String)
        XCTAssertEqual(report()["audioStarts"] as? Int, 1)
        XCTAssertEqual(report()["audioArtifactBytes"] as? Int, 8)
        XCTAssertEqual(report()["favoriteCount"] as? Int, 1)
        XCTAssertEqual(app.staticTexts["offlineSettings.complete"].label, "Tekst og lyd klar offline: 1 af 1")
        captureAudio("Automatic offline — complete text and verified audio receipt are ready",
            required: [app.staticTexts["offlineSettings.complete"], app.staticTexts["offlineSettings.audioAvailable"]])
        // The production tag presents its label in uppercase, like the other article tags.
        XCTAssertEqual(bodyStatus.label, "GEMT")
        captureAudio("Automatic offline — shared article control is saved only after both actual components", required: [bodyStatus])
        tap("offlineSettings.fixture.goOffline")
        wait("Local offline presentation preserves the same original saved article and audio") {
            $0["isOnline"] as? Bool == false && $0["combinedReady"] as? Int == 1
                && $0["audioDownloadedForMember"] as? Bool == true
        }
        XCTAssertEqual(report()["audioStarts"] as? Int, 1)
        XCTAssertEqual(report()["writes"] as? Int, 1)
        XCTAssertEqual(report()["audioAccessLease"] as? String, before["audioAccessLease"] as? String)
        captureAudio("Automatic offline — local offline flag retains exact body and audio receipt",
            required: [app.staticTexts["offlineSettings.complete"]])
    }

    func testActualAudioFailureStaysNotReadyUntilExplicitRecoveryCompletesOneNewAttempt() {
        launch("audioFailure")
        tap("offlineSettings.fixture.seed")
        wait("The ordinary save starts its first actual held audio attempt") {
            $0["available"] as? Int == 1 && $0["audioStarts"] as? Int == 1 && $0["heldAudio"] as? Int == 1
        }
        let lease = report()["audioAccessLease"] as? String
        tap("offlineSettings.fixture.failAudio")
        wait("A real transport failure leaves text saved and combined status not ready") {
            $0["audioState"] as? String == "failed" && $0["audioFailedEvents"] as? Int == 1
                && $0["heldAudio"] as? Int == 0 && $0["combinedReady"] as? Int == 0
                && $0["combinedFailed"] as? Int == 1
        }
        XCTAssertEqual(app.staticTexts["offlineSettings.complete"].label, "Tekst og lyd klar offline: 0 af 1")
        XCTAssertTrue(app.staticTexts["offlineSettings.audioFailed"].exists)
        XCTAssertEqual(app.staticTexts["offline.body.status"].label, "Lyden kunne ikke hentes")
        captureAudio("Automatic offline — actual failed audio is separate from saved text",
            required: [app.staticTexts["offlineSettings.audioFailed"]])
        captureAudio("Automatic offline — actual shared article control does not turn green after failed audio",
            required: [app.staticTexts["offline.body.status"]])
        redrawWithoutIO(2)
        XCTAssertEqual(report()["audioStarts"] as? Int, 1)
        XCTAssertEqual(report()["audioSavedEvents"] as? Int, 0)
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.report()["audioStarts"] as? Int != 1
        }, object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 1), .completed,
            "A display redraw or slot drain must not create a failed-download retry loop")
        tap("offlineSettings.fixture.recoverAudio")
        wait("One explicit recovery event starts precisely one new actual attempt") {
            $0["audioStarts"] as? Int == 2 && $0["heldAudio"] as? Int == 1
                && $0["combinedReady"] as? Int == 0
        }
        XCTAssertEqual(report()["audioAccessLease"] as? String, lease)
        tap("offlineSettings.fixture.releaseAudio")
        wait("Recovered audio has its actual complete receipt before saved status") {
            $0["combinedReady"] as? Int == 1 && $0["audioSavedEvents"] as? Int == 1
                && $0["audioDownloadedForMember"] as? Bool == true && $0["heldAudio"] as? Int == 0
        }
        XCTAssertEqual(report()["audioStarts"] as? Int, 2)
        XCTAssertEqual(report()["audioFailedEvents"] as? Int, 1)
        XCTAssertEqual(report()["audioArtifactBytes"] as? Int, 8)
        XCTAssertEqual(report()["audioAccessLease"] as? String, lease)
        XCTAssertEqual(app.staticTexts["offline.body.status"].label, "GEMT")
        captureAudio("Automatic offline — explicit recovery restores complete current-member readiness",
            required: [app.staticTexts["offlineSettings.complete"], app.staticTexts["offlineSettings.audioAvailable"]])
    }

    private func captureAudio(_ name: String, required: [XCUIElement]) {
        expose(required)
        required.forEach { XCTAssertTrue(fullyVisible($0), $0.identifier) }
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        var receipt = report()
        receipt["captureFrames"] = required.map { element in
            ["id": element.identifier, "label": element.label,
             "x": element.frame.minX, "y": element.frame.minY,
             "width": element.frame.width, "height": element.frame.height] as [String: Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
            let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            json.name = name + " — actual cache, original membership and measured frames"
            json.lifetime = .keepAlways; add(json)
        }
    }
}
