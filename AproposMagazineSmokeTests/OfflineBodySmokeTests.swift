import XCTest

final class OfflineBodySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposOfflineBodySmoke", "-OfflineBodyScenario", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["offline.fixture.firebase"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["offline.fixture.firebase"].label, "Firebase: ikke startet")
        waitLabel("offline.fixture.ready", "Klar")
        let textSize = app.staticTexts["offline.fixture.textSize"]
        XCTAssertTrue(textSize.exists)
        let accessibility = textSize.value as? String == "System: tilgængelighed"
        XCTAssertEqual(textSize.label, accessibility ? "Tilgængelighedstekst" : "Normal tekst",
                       "The actual shared control must inherit the system size, unlike the clamped fixture diagnostics")
        XCTContext.runActivity(named: "Actual system text: \(textSize.value as? String ?? "missing")") { _ in }
    }
    private func waitLabel(_ id: String, _ value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func status(_ state: String, label: String) {
        waitLabel("offline.fixture.state", "Status: \(state)")
        waitLabel("offline.body.status", label)
    }
    private func capture(_ name: String) {
        revealFeedback()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<5 {
            if button.isHittable { button.tap(); return }
            if button.exists && button.frame.maxY < app.navigationBars.firstMatch.frame.maxY {
                app.swipeDown()
            } else { app.swipeUp() }
        }
        XCTFail("Expected reachable action \(id)")
    }
    private func retry(label: String) {
        let button = app.buttons["offline.body.retry"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let accessibilityLabel = label == "Prøv igen" ? "Prøv at hente artikelteksten igen" : "Hent artikeltekst til offlinelæsning"
        XCTAssertEqual(button.label, accessibilityLabel)
        revealFeedback()
        XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44)
        capture("Offline — synlig status og \(label) før tryk")
        button.tap()
    }
    private func revealFeedback() {
        let status = app.staticTexts["offline.body.status"], retry = app.buttons["offline.body.retry"]
        let scroll = app.scrollViews.firstMatch
        let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 4
        let bottom = min(scroll.frame.maxY, app.frame.maxY - 24) - 4
        for _ in 0..<6 {
            let frame = retry.exists ? status.frame.union(retry.frame) : status.frame
            if frame.minY >= top && frame.maxY <= bottom { break }
            let upward = frame.maxY > bottom
            let excess = upward ? frame.maxY - bottom : top - frame.minY
            let distance = min(200, max(60, excess + 20)), center = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: center + (upward ? distance / 2 : -distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: center + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThan(status.frame.height, 0)
        XCTAssertGreaterThanOrEqual(status.frame.minX, app.frame.minX + 15)
        XCTAssertLessThanOrEqual(status.frame.maxX, app.frame.maxX - 15)
        XCTAssertGreaterThanOrEqual(status.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(status.frame.maxY, bottom + 1)
        if retry.exists {
            XCTAssertTrue(retry.isHittable)
            XCTAssertGreaterThanOrEqual(retry.frame.minY, top - 1)
            XCTAssertLessThanOrEqual(retry.frame.maxY, bottom + 1)
        }
    }

    func testHeldFetchShowsPendingUntilActualBodySaveSucceeds() {
        launch("held")
        status("pending", label: "Henter artikeltekst…")
        waitLabel("offline.fixture.body", "Tekst: ikke gemt")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        capture("Offline — henter tekst uden at love lokal kopi")
        tap("offline.fixture.release")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.body", "Tekst: tilgængelig")
        waitLabel("offline.fixture.writes", "Skrivninger: 1")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        capture("Offline — faktisk gemt artikeltekst")
    }

    func testFetchFailureOffersExplicitRetryAndThenRealSavedText() {
        launch("fetchFailure")
        status("failed", label: "Teksten kunne ikke downloades")
        waitLabel("offline.fixture.body", "Tekst: ikke gemt")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        capture("Offline — henteafvisning med lokal prøve igen")
        retry(label: "Prøv igen")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.body", "Tekst: tilgængelig")
        waitLabel("offline.fixture.fetches", "Hentninger: 2")
        waitLabel("offline.fixture.writes", "Skrivninger: 1")
        capture("Offline — henteafvisning genoprettet")
    }

    func testWriteFailureNeverClaimsOfflineUntilRetryActuallyWrites() {
        launch("writeFailure")
        status("failed", label: "Teksten kunne ikke downloades")
        waitLabel("offline.fixture.body", "Tekst: ikke gemt")
        waitLabel("offline.fixture.writes", "Skrivninger: 1")
        capture("Offline — lokal skrivefejl uden falsk klarstatus")
        retry(label: "Prøv igen")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.body", "Tekst: tilgængelig")
        waitLabel("offline.fixture.writes", "Skrivninger: 2")
    }

    func testAccountRoundTripRejectsOriginalFetchAndNeedsExplicitCurrentRetry() {
        launch("accountRoundTrip")
        status("pending", label: "Henter artikeltekst…")
        tap("offline.fixture.roundTrip")
        waitLabel("offline.fixture.owner", "Ny A-generation")
        status("notDownloaded", label: "Tekst ikke downloadet")
        tap("offline.fixture.release")
        waitLabel("offline.fixture.held", "Afventer: 0")
        status("notDownloaded", label: "Tekst ikke downloadet")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        waitLabel("offline.fixture.body", "Tekst: ikke gemt")
        capture("Offline — gammel A-hentning må ikke blive ny A-kopi")
        retry(label: "Hent tekst")
        status("pending", label: "Henter artikeltekst…")
        waitLabel("offline.fixture.fetches", "Hentninger: 2")
        tap("offline.fixture.release")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.body", "Tekst: tilgængelig")
        waitLabel("offline.fixture.writes", "Skrivninger: 1")
        XCTAssertEqual(app.staticTexts["offline.fixture.firebase"].label, "Firebase: ikke startet")
    }

    func testColdStoredBodyChecksOnceAcrossRedrawsAndRevalidatesMissingBytes() {
        launch("coldStored")
        status("checking", label: "Kontrollerer offlineindhold…")
        waitLabel("offline.fixture.probes", "Kontroller: 1")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 1")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        waitLabel("offline.fixture.fetches", "Hentninger: 0")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        capture("Offline — kontrollerer kold lokal kopi uden tidlig klarstatus")

        for count in 1...3 {
            tap("offline.fixture.redraw")
            waitLabel("offline.fixture.redraws", "Gentegninger: \(count)")
            waitLabel("offline.fixture.probes", "Kontroller: 1")
            waitLabel("offline.fixture.indexReads", "Synkrone indekslæsninger: 0")
            waitLabel("offline.fixture.bodyReads", "Tekstlæsninger: 0")
        }
        tap("offline.fixture.releaseProbe")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 0")
        capture("Offline — accepteret lokal kontrol uden renderlæsning")
        tap("offline.fixture.redraw")
        waitLabel("offline.fixture.redraws", "Gentegninger: 4")
        waitLabel("offline.fixture.probes", "Kontroller: 1")
        waitLabel("offline.fixture.indexReads", "Synkrone indekslæsninger: 0")
        waitLabel("offline.fixture.bodyReads", "Tekstlæsninger: 0")

        tap("offline.fixture.removeStoredBody")
        status("checking", label: "Kontrollerer offlineindhold…")
        waitLabel("offline.fixture.probes", "Kontroller: 2")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 1")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        capture("Offline — fornyet kontrol skjuler gammel klarstatus")
        tap("offline.fixture.releaseProbe")
        status("notDownloaded", label: "Tekst ikke downloadet")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 0")
        waitLabel("offline.fixture.indexReads", "Synkrone indekslæsninger: 0")
        waitLabel("offline.fixture.bodyReads", "Tekstlæsninger: 0")
        waitLabel("offline.fixture.fetches", "Hentninger: 0")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        capture("Offline — fjernede bytes kræver eksplicit hentning")
        XCTAssertTrue(app.buttons["offline.body.retry"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["offline.body.retry"].frame.height + 0.001, 44)
    }

    func testOldAccountProbeCannotMakeReturnedAccountOfflineReady() {
        launch("probeAccountRoundTrip")
        status("checking", label: "Kontrollerer offlineindhold…")
        waitLabel("offline.fixture.probes", "Kontroller: 1")
        tap("offline.fixture.roundTrip")
        waitLabel("offline.fixture.owner", "Ny A-generation")
        status("checking", label: "Kontrollerer offlineindhold…")
        waitLabel("offline.fixture.probes", "Kontroller: 2")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 2")

        tap("offline.fixture.releaseProbe")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 1")
        status("checking", label: "Kontrollerer offlineindhold…")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        waitLabel("offline.fixture.fetches", "Hentninger: 0")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        capture("Offline — gammel positiv A-kontrol giver ikke ny adgang")

        tap("offline.fixture.releaseProbe")
        waitLabel("offline.fixture.heldProbes", "Afventer kontrol: 0")
        status("notDownloaded", label: "Tekst ikke downloadet")
        waitLabel("offline.fixture.probes", "Kontroller: 2")
        waitLabel("offline.fixture.indexReads", "Synkrone indekslæsninger: 0")
        waitLabel("offline.fixture.bodyReads", "Tekstlæsninger: 0")
        waitLabel("offline.fixture.writes", "Skrivninger: 0")
        capture("Offline — kun den aktuelle kontrol bestemmer status")
        XCTAssertEqual(app.staticTexts["offline.fixture.firebase"].label, "Firebase: ikke startet")
    }

    func testPublishedRevisionRecoveryPersistsAndColdOfflineRendererShowsActualSavedText() throws {
        launch("publishedRecovery")
        status("notDownloaded", label: "Tekst ikke downloadet")
        waitLabel("offline.fixture.recoveryStage", "Ældre gemt artikel")
        let before = try recoveryProof()
        let fixtureID = try XCTUnwrap(before["fixtureID"] as? String)
        XCTAssertEqual(before["oldRevision"] as? String, "updated:2026-10-24T11:00:00Z")
        XCTAssertEqual(before["currentRevision"] as? String, before["oldRevision"] as? String)
        XCTAssertEqual(before["selectedArticleIDs"] as? [String], ["offline-body-fixture"])
        XCTAssertEqual(before["pendingIntentCount"] as? Int, 0)
        XCTAssertEqual(before["bodyWrites"] as? Int, 0)
        captureRecovery("Offline recovery — faktisk kold ældre favorit før ny kilde", proof: before)

        tap("offline.fixture.adoptPublished")
        status("pending", label: "Henter artikeltekst…")
        waitLabel("offline.fixture.body", "Tekst: ikke gemt")
        waitLabel("offline.fixture.held", "Afventer: 1")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        let pending = try recoveryProof()
        XCTAssertEqual(pending["fixtureID"] as? String, fixtureID)
        XCTAssertEqual(pending["currentRevision"] as? String, "local-offline-r1")
        XCTAssertEqual(pending["sourceAdopted"] as? Bool, true)
        XCTAssertNotEqual(pending["originalContentKey"] as? String, pending["currentContentKey"] as? String)
        XCTAssertEqual(pending["selectedArticleIDs"] as? [String], ["offline-body-fixture"])
        XCTAssertEqual(pending["pendingIntentCount"] as? Int, 0)
        XCTAssertEqual(pending["bodyWrites"] as? Int, 0)
        captureRecovery("Offline recovery — ny billet afventer den virkelige bodyhentning", proof: pending)

        tap("offline.fixture.release")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.body", "Tekst: tilgængelig")
        waitLabel("offline.fixture.writes", "Skrivninger: 1")
        let saved = try recoveryProof()
        XCTAssertEqual(saved["fixtureID"] as? String, fixtureID)
        XCTAssertEqual(saved["hasDecodedBody"] as? Bool, true)
        XCTAssertGreaterThan(saved["decodedHTMLBytes"] as? Int ?? 0, 0)
        XCTAssertEqual(saved["coldRestored"] as? Bool, false)
        captureRecovery("Offline recovery — faktisk gemt body og indeks", proof: saved)

        tap("offline.fixture.coldRead")
        waitLabel("offline.fixture.recoveryStage", "Kold offlineartikel")
        status("available", label: "GEMT")
        waitLabel("offline.fixture.webState", "Webtekst: ready")
        let cold = try recoveryProof()
        XCTAssertEqual(cold["fixtureID"] as? String, fixtureID)
        XCTAssertEqual(cold["coldRestored"] as? Bool, true)
        XCTAssertEqual(cold["hasDecodedBody"] as? Bool, true)
        XCTAssertEqual(cold["currentContentKey"] as? String, pending["currentContentKey"] as? String)
        XCTAssertEqual(cold["currentRevision"] as? String, "local-offline-r1")
        XCTAssertEqual(cold["pendingIntentCount"] as? Int, 0)
        XCTAssertEqual(cold["bodyWrites"] as? Int, 1)
        XCTAssertEqual(cold["fetches"] as? Int, 1, "Cold opening never starts a network substitute")
        XCTAssertEqual(cold["firebaseStarted"] as? Bool, false)
        XCTAssertFalse(app.staticTexts["offline.fixture.recoveryFailure"].exists)
        let actualText = app.webViews.staticTexts["Denne lokale artikeltekst er gemt gennem den faktiske offlinekoordinator."]
        XCTAssertTrue(actualText.waitForExistence(timeout: 8), "The saved HTML must be present in the product WebKit renderer")
        let indicator = app.descendants(matching: .any)["offline.fixture.offlineIndicator"]
        revealColdOfflineBody(actualText, indicator: indicator)
        XCTAssertTrue(actualText.isHittable, "The actual decoded body must be visible, including at largest system text")
        XCTAssertTrue(indicator.isHittable, "The local offline indicator and actual renderer must be visible together")
        captureRecovery("Offline recovery — kold diskafkodning i faktisk ArticleHTMLBody", proof: cold, revealStatus: false)
    }

    func testCombinedDownloadProgressKeepsActualHeaderNotSavedUntilBothProofsExist() throws {
        launch("downloadProgress")
        status("available", label: "Henter 0 %")
        let original = try progressProof()
        XCTAssertFalse(try XCTUnwrap(original["leaseID"] as? String).isEmpty)
        XCTAssertEqual(original["bodyWrites"] as? Int, 1)
        XCTAssertEqual(original["bodyFetches"] as? Int, 1)
        XCTAssertEqual(original["audioState"] as? String, "downloading")
        XCTAssertEqual(original["audioProgress"] as? Double, 0)
        XCTAssertEqual(original["audioProof"] as? Bool, false)
        XCTAssertEqual(original["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — current saved text, audio at actual supplied 0 percent", original: original)

        tap("offline.fixture.progress42")
        status("available", label: "Henter 42 %")
        let active = try progressProof()
        XCTAssertEqual(active["audioProgress"] as? Double, 0.42)
        XCTAssertEqual(active["audioProof"] as? Bool, false)
        XCTAssertEqual(active["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — current audio progress 42 percent in production tag flow", original: original)

        tap("offline.fixture.progressFull")
        status("available", label: "Henter 99 %")
        let bytesReceived = try progressProof()
        XCTAssertEqual(bytesReceived["rawProgress"] as? Double, 1)
        XCTAssertEqual(bytesReceived["audioProgress"] as? Double, 1, "Only the presentation caps a complete byte count before verification")
        XCTAssertEqual(bytesReceived["audioState"] as? String, "downloading")
        XCTAssertEqual(bytesReceived["audioProof"] as? Bool, false)
        XCTAssertEqual(bytesReceived["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — full byte count is capped at 99 until existing proof accepts completion", original: original)

        tap("offline.fixture.progressComplete")
        status("available", label: "GEMT")
        let saved = try progressProof()
        XCTAssertEqual(saved["audioState"] as? String, "available")
        XCTAssertEqual(saved["audioProof"] as? Bool, true)
        XCTAssertEqual(saved["combinedReady"] as? Int, 1)
        XCTAssertEqual(saved["audioRetries"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — GEMT only when the same article has text and admitted audio proof", original: original)
    }

    func testMissingOfflineAudioShowsPartialSaveWithoutFailureRetry() throws {
        launch("downloadProgress")
        status("available", label: "Henter 0 %")
        let original = try progressProof()
        tap("offline.fixture.progressWaiting")
        try revealProgressHeader()
        revealFeedback()
        var observed = try progressProof()
        observed["observedStatus"] = app.staticTexts["offline.body.status"].label
        observed["observedRetry"] = app.buttons["offline.body.retry"].exists
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Missing offline audio — actual partial save before copy and retry assertions"
        screenshot.lifetime = .keepAlways; add(screenshot)
        let data = try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys])
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = "Missing offline audio — unchanged original body and audio proof"
        receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertEqual(observed["fixtureID"] as? String, original["fixtureID"] as? String)
        XCTAssertEqual(observed["leaseID"] as? String, original["leaseID"] as? String)
        XCTAssertEqual(observed["bodyState"] as? String, "available")
        XCTAssertEqual(observed["bodyWrites"] as? Int, 1)
        XCTAssertEqual(observed["audioState"] as? String, "waitingForPublication")
        XCTAssertEqual(observed["audioProof"] as? Bool, false)
        XCTAssertEqual(observed["combinedReady"] as? Int, 0)
        XCTAssertEqual(observed["audioRetries"] as? Int, 0)
        XCTAssertTrue(observed["audioProgress"] is NSNull)
        XCTAssertEqual(app.staticTexts["offline.body.status"].label, "Tekst gemt · lyd ikke hentet")
        XCTAssertFalse(app.buttons["offline.body.retry"].exists, "Waiting for an admitted offline asset is not a failed transfer")
    }

    func testUnknownWaitingAndFailedAudioNeverInventPercentOrSavedStatus() throws {
        launch("downloadProgress")
        status("available", label: "Henter 0 %")
        let original = try progressProof()

        tap("offline.fixture.progressUnknown")
        status("available", label: "Henter lyd…")
        let unknown = try progressProof()
        XCTAssertTrue(unknown["audioProgress"] is NSNull, "An unknown total must stay indeterminate")
        XCTAssertEqual(unknown["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — unknown audio total has no fabricated percentage", original: original)

        tap("offline.fixture.progressMissing")
        status("available", label: "Kontrollerer gemt lyd…")
        let unresolved = try progressProof()
        XCTAssertEqual(unresolved["audioState"] as? String, "none")
        XCTAssertEqual(unresolved["missingCapturedAudioState"] as? Bool, true)
        XCTAssertEqual(unresolved["rawProgress"] as? Double, 0.42)
        XCTAssertEqual(unresolved["audioProof"] as? Bool, false)
        XCTAssertEqual(unresolved["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — missing captured audio state suppresses even stale numeric progress", original: original)

        tap("offline.fixture.progressWaiting")
        status("available", label: "Tekst gemt · lyd ikke hentet")
        let waiting = try progressProof()
        XCTAssertEqual(waiting["audioState"] as? String, "waitingForPublication")
        XCTAssertEqual(waiting["rawProgress"] as? Double, 0.42)
        XCTAssertTrue(waiting["audioProgress"] is NSNull, "Old progress cannot survive loss of the admitted source")
        XCTAssertEqual(waiting["combinedReady"] as? Int, 0)
        try captureProgress("Download pill — missing offline audio keeps saved text without a failure retry", original: original)

        tap("offline.fixture.progressFailure")
        status("available", label: "Lyden kunne ikke hentes")
        let failed = try progressProof()
        XCTAssertEqual(failed["audioState"] as? String, "failed")
        XCTAssertTrue(failed["audioProgress"] is NSNull)
        XCTAssertEqual(failed["audioProof"] as? Bool, false)
        XCTAssertEqual(failed["combinedReady"] as? Int, 0)
        XCTAssertEqual(failed["audioRetries"] as? Int, 0)
        try captureProgress("Download pill — failed audio preserves text and offers the real explicit retry", original: original, retryExpected: true)
        let retry = app.buttons["offline.body.retry"]
        XCTAssertEqual(retry.label, "Hent tekst og lyd til offlinebrug")
        retry.tap()
        status("available", label: "Henter 0 %")
        let retried = try progressProof()
        XCTAssertEqual(retried["audioRetries"] as? Int, 1)
        XCTAssertEqual(retried["audioState"] as? String, "downloading")
        XCTAssertEqual(retried["combinedReady"] as? Int, 0)
        XCTAssertFalse(app.buttons["offline.body.retry"].exists)
        try captureProgress("Download pill — one explicit retry returns to a truthful current 0 percent", original: original)
    }

    private func progressProof() throws -> [String: Any] {
        let report = app.staticTexts["offline.fixture.progressProof"]
        XCTAssertTrue(report.exists)
        let text = try XCTUnwrap(report.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func captureProgress(_ name: String, original: [String: Any], retryExpected: Bool = false) throws {
        try revealProgressHeader()
        revealFeedback()
        let report = try progressProof()
        for key in ["fixtureID", "articleID", "revision", "leaseID", "namespace"] {
            XCTAssertEqual(report[key] as? String, original[key] as? String, "Progress must remain bound to the original \(key)")
        }
        XCTAssertEqual(report["bodyState"] as? String, "available")
        XCTAssertEqual(report["bodyWrites"] as? Int, 1)
        XCTAssertEqual(report["bodyFetches"] as? Int, 1)
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
        XCTAssertEqual(report["fixtureAudioEffectsAreMemoryOnly"] as? Bool, true)
        XCTAssertEqual(report["environmentAccessibility"] as? Bool, report["systemAccessibility"] as? Bool)
        let frames = try XCTUnwrap(report["frames"] as? [String: [String: Double]])
        func frame(_ key: String) throws -> CGRect {
            let item = try XCTUnwrap(frames[key], "The production header must report its actual \(key) frame")
            let rect = CGRect(x: try XCTUnwrap(item["x"]), y: try XCTUnwrap(item["y"]),
                              width: try XCTUnwrap(item["width"]), height: try XCTUnwrap(item["height"]))
            XCTAssertGreaterThan(rect.width, 0); XCTAssertGreaterThan(rect.height, 0)
            return rect
        }
        let container = try frame("container"), status = try frame("status")
        XCTAssertGreaterThanOrEqual(status.minX, container.minX - 1)
        XCTAssertLessThanOrEqual(status.maxX, container.maxX + 1)
        for key in ["chip.author", "chip.category.0", "chip.category.1"] {
            let chip = try frame(key)
            XCTAssertGreaterThanOrEqual(chip.minX, container.minX - 1)
            XCTAssertLessThanOrEqual(chip.maxX, container.maxX + 1)
            XCTAssertFalse(status.insetBy(dx: 0.5, dy: 0.5).intersects(chip.insetBy(dx: 0.5, dy: 0.5)),
                           "The current status and editorial tag must occupy separate non-overlapping flow slots")
        }
        let retry = app.buttons["offline.body.retry"]
        XCTAssertEqual(retry.exists, retryExpected)
        if retryExpected {
            XCTAssertTrue(retry.isHittable)
            XCTAssertGreaterThanOrEqual(retry.frame.height + 0.001, 44)
            XCTAssertGreaterThanOrEqual(retry.frame.width + 0.001, 44)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        var evidence = report
        evidence["captureLabel"] = app.staticTexts["offline.body.status"].label
        evidence["captureStatusFrame"] = ["x": app.staticTexts["offline.body.status"].frame.minX,
            "y": app.staticTexts["offline.body.status"].frame.minY,
            "width": app.staticTexts["offline.body.status"].frame.width,
            "height": app.staticTexts["offline.body.status"].frame.height]
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = name + " — original session, proof and header geometry"; json.lifetime = .keepAlways; add(json)
    }

    private func revealProgressHeader() throws {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let report = try progressProof()
            guard let frames = report["frames"] as? [String: [String: Double]],
                  let header = frames["container"], let x = header["x"], let y = header["y"],
                  let width = header["width"], let height = header["height"] else {
                XCTFail("The shared header must finish its actual geometry probe"); return
            }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 8
            let bottom = min(scroll.frame.maxY, app.frame.maxY - 24) - 8
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertLessThanOrEqual(frame.height, bottom - top,
                                     "The complete shared tag group must fit, including at the real maximum text size")
            if frame.minY >= top && frame.maxY <= bottom { return }
            let upward = frame.maxY > bottom
            let excess = upward ? frame.maxY - bottom : top - frame.minY
            let distance = min(200, max(40, excess + 16)), center = (top + bottom) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: center + (upward ? distance / 2 : -distance / 2)))
            let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: center + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("The complete production header must be visible before the original screen capture")
    }

    private func revealColdOfflineBody(_ text: XCUIElement, indicator: XCUIElement) {
        let scroll = app.scrollViews.firstMatch
        func viewport() -> CGRect {
            let frame = scroll.frame.intersection(app.frame)
            let top = max(frame.minY, app.navigationBars.firstMatch.frame.maxY) + 8
            let bottom = min(frame.maxY, app.frame.maxY - 24) - 8
            return CGRect(x: frame.minX + 8, y: top, width: frame.width - 16, height: bottom - top)
        }
        func near(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
                && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
        }
        for attempt in 0..<12 {
            let visible = viewport()
            let textFrame = text.frame, indicatorFrame = indicator.frame
            let required = textFrame.union(indicatorFrame)
            XCTAssertFalse(visible.isEmpty)
            XCTAssertGreaterThan(textFrame.height, 0)
            XCTAssertGreaterThan(indicatorFrame.height, 0)
            XCTAssertLessThanOrEqual(required.height, visible.height,
                                     "The whole saved paragraph and offline indicator must fit the capture viewport together")
            if visible.contains(required) {
                // This only settles capture after measured containment, never waits for save/download success.
                Thread.sleep(forTimeInterval: 0.2)
                let settledViewport = viewport(), settledText = text.frame, settledIndicator = indicator.frame
                if settledViewport.contains(settledText.union(settledIndicator)),
                   near(textFrame, settledText), near(indicatorFrame, settledIndicator), near(visible, settledViewport) {
                    let receipt = "Measured cold capture after \(attempt) pans: viewport=\(settledViewport), text=\(settledText), offlineIndicator=\(settledIndicator); both whole frames contained after 0.2s capture settling."
                    let attachment = XCTAttachment(string: receipt)
                    attachment.name = "Cold renderer — actual paragraph and offline indicator capture geometry"
                    attachment.lifetime = .keepAlways; add(attachment)
                    return
                }
                continue
            }
            let upward = required.maxY > visible.maxY
            let excess = upward ? required.maxY - visible.maxY : visible.minY - required.minY
            let distance = min(visible.height / 2, max(40, excess + 16))
            let center = visible.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: center + (upward ? distance / 2 : -distance / 2)))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: center + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("The saved paragraph and offline indicator must be wholly inside a stable measured viewport before capture; text=\(text.frame), indicator=\(indicator.frame), viewport=\(viewport())")
    }

    private func recoveryProof() throws -> [String: Any] {
        let receipt = app.staticTexts["offline.fixture.recoveryProof"]
        XCTAssertTrue(receipt.exists)
        let text = try XCTUnwrap(receipt.value as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func captureRecovery(_ name: String, proof: [String: Any], revealStatus: Bool = true) {
        if revealStatus { revealFeedback() }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        if let data = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = name + " — revisions- og diskbevis"; receipt.lifetime = .keepAlways; add(receipt)
        }
    }
}
