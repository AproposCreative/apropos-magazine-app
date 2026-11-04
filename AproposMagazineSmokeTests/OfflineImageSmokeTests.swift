import XCTest

final class OfflineImageSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposOfflineImageSmoke", "-OfflineImageScenario", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["offlineImage.firebase"].waitForExistence(timeout: 8))
        waitLabel("offlineImage.firebase", "Firebase: ikke startet")
        waitLabel("offlineImage.ready", "Klar")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let report = self?.report(), let frames = report["frames"] as? [String: Any] else { return false }
            return ["cover", "credit", "thumbnail", "row"].allSatisfy { frames[$0] != nil }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let payload = report()
        XCTAssertEqual(payload["environmentAccessibility"] as? Bool, payload["systemAccessibility"] as? Bool,
                       "Only fixture diagnostics may clamp Dynamic Type; actual image context inherits the system setting")
        XCTContext.runActivity(named: "System text: \(payload["systemCategory"] as? String ?? "missing")") { _ in }
    }
    private func waitLabel(_ id: String, _ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed, "Expected \(id): \(value)")
    }
    private func count(_ id: String) -> Int {
        Int(app.staticTexts[id].label.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? -1
    }
    private func waitCount(_ id: String, atLeast minimum: Int) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            (self?.count(id) ?? -1) >= minimum
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed, "Expected \(id) >= \(minimum)")
    }
    private func report() -> [String: Any] {
        guard let value = app.staticTexts["offlineImage.geometry"].value as? String,
              let data = value.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return decoded
    }
    private func frame(_ key: String, in payload: [String: Any]? = nil) -> CGRect {
        guard let frames = (payload ?? report())["frames"] as? [String: [String: Double]], let values = frames[key],
              let x = values["x"], let y = values["y"], let width = values["width"], let height = values["height"] else {
            XCTFail("Missing actual frame \(key)"); return .zero
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable)
        button.tap()
    }
    private func checkFrames(online: Bool = false) -> [String: Any] {
        let payload = report(), cover = frame("cover", in: payload), credit = frame("credit", in: payload)
        let thumb = frame("thumbnail", in: payload), row = frame("row", in: payload)
        XCTAssertEqual(cover.minX, app.frame.minX + 16, accuracy: 1)
        XCTAssertEqual(cover.maxX, app.frame.maxX - 16, accuracy: 1)
        XCTAssertGreaterThanOrEqual(cover.height, 220 - 0.5)
        XCTAssertLessThanOrEqual(cover.height, 340 + 0.5)
        XCTAssertEqual(credit.minX, cover.minX, accuracy: 1)
        XCTAssertEqual(credit.maxX, cover.maxX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(credit.minY, cover.maxY - 0.5)
        XCTAssertLessThanOrEqual(credit.minY - cover.maxY, 16.5)
        XCTAssertGreaterThan(credit.height, 0)
        XCTAssertEqual(thumb.width, 80, accuracy: 0.5)
        XCTAssertEqual(thumb.height, 80, accuracy: 0.5)
        XCTAssertEqual(thumb.minX, app.frame.minX + 16, accuracy: 1)
        XCTAssertEqual(thumb.maxY, row.maxY, accuracy: 1)
        XCTAssertEqual(count("offlineImage.mainReads"), 0)
        if !online {
            XCTAssertEqual(count("offlineImage.fallback"), 0, "The local original fallback is magenta, never a network URL")
        }
        return payload
    }
    private func assertGeometryPreserved(_ before: [String: Any], online: Bool = false) {
        let after = checkFrames(online: online)
        for key in ["cover", "credit", "thumbnail"] {
            XCTAssertEqual(frame(key, in: before).width, frame(key, in: after).width, accuracy: 0.5)
            XCTAssertEqual(frame(key, in: before).height, frame(key, in: after).height, accuracy: 0.5)
        }
        let beforeGap = frame("credit", in: before).minY - frame("cover", in: before).maxY
        let afterGap = frame("credit", in: after).minY - frame("cover", in: after).maxY
        XCTAssertEqual(beforeGap, afterGap, accuracy: 0.5)
    }
    private func capture(_ name: String, row: Bool = false) {
        let scroll = app.scrollViews["offlineImage.scroll"]
        let top = scroll.frame.minY + 4, bottom = min(scroll.frame.maxY, app.frame.maxY - 20) - 4
        for _ in 0..<8 {
            let target = row ? frame("row") : frame("cover").union(frame("credit"))
            if target.minY >= top && target.maxY <= bottom { break }
            let upward = target.maxY > bottom
            let excess = upward ? target.maxY - bottom : top - target.minY
            let distance = min(220, max(40, excess + 8)), center = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,
                dy: center + (upward ? distance / 2 : -distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,
                dy: center + (upward ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let target = row ? frame("row") : frame("cover").union(frame("credit"))
        XCTAssertGreaterThanOrEqual(target.minY, top - 1)
        XCTAssertLessThanOrEqual(target.maxY, bottom + 1)
        let geometry = XCTAttachment(string: app.staticTexts["offlineImage.geometry"].value as? String ?? "missing")
        geometry.name = "\(name) — actual geometry"; geometry.lifetime = .keepAlways; add(geometry)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func decoded(_ color: String) {
        waitLabel("offlineImage.coverState", "Cover: Klar: \(color)")
        waitLabel("offlineImage.rowState", "Række: Klar: \(color)")
        waitCount("offlineImage.decoded", atLeast: 2)
        XCTAssertEqual(app.staticTexts["offlineImage.firebase"].label, "Firebase: ikke startet")
    }
    private func settledOnlineCounters() -> [String: Int] {
        let keys = ["offlineImage.prepares", "offlineImage.starts", "offlineImage.decoded", "offlineImage.reads"]
        var candidate = Dictionary(uniqueKeysWithValues: keys.map { ($0, count($0)) })
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            let current = Dictionary(uniqueKeysWithValues: keys.map { ($0, self.count($0)) })
            if current != candidate { candidate = current; stableSince = Date() }
            let bothDecoded = self.app.staticTexts["offlineImage.coverState"].label == "Cover: Klar: magenta fallback"
                && self.app.staticTexts["offlineImage.rowState"].label == "Række: Klar: magenta fallback"
            if !bothDecoded { stableSince = Date(); return false }
            return Date().timeIntervalSince(stableSince) >= 1
                && (current["offlineImage.prepares"] ?? -1) >= 2
                && (current["offlineImage.starts"] ?? -1) >= 2
                && (current["offlineImage.decoded"] ?? -1) >= 2
                && current["offlineImage.reads"] == 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed,
                       "Settle legitimate launch/foreground revalidation before unrelated cache mutation")
        let evidence = XCTAttachment(string: String(describing: candidate))
        evidence.name = "Frozen settled counters before unrelated eviction"; evidence.lifetime = .keepAlways; add(evidence)
        return candidate
    }

    func testHeldColdLookupNeverStartsFallbackBeforeLocalPreparation() {
        launch("heldCold")
        waitCount("offlineImage.reads", atLeast: 1)
        waitLabel("offlineImage.coverState", "Cover: Klargør")
        waitLabel("offlineImage.rowState", "Række: Klargør")
        XCTAssertEqual(count("offlineImage.starts"), 0)
        XCTAssertEqual(count("offlineImage.decoded"), 0)
        let geometry = checkFrames()
        capture("Cold image — actual placeholders while mapping read is held")
        tap("offlineImage.releaseAll")
        decoded("grøn")
        assertGeometryPreserved(geometry)
        capture("Cold image — actual WebImage decoded green local cover")
        capture("Cold image — actual WebImage decoded green local row", row: true)
    }

    func testWideColdImagePreservesCoverSlotAndCreditAfterDecode() {
        launch("heldColdWide")
        waitCount("offlineImage.reads", atLeast: 1)
        waitLabel("offlineImage.coverState", "Cover: Klargør")
        waitLabel("offlineImage.rowState", "Række: Klargør")
        XCTAssertEqual(count("offlineImage.starts"), 0)
        XCTAssertEqual(count("offlineImage.decoded"), 0)
        let geometry = checkFrames()
        capture("Wide cold image — actual placeholders before 160×90 decode")
        tap("offlineImage.releaseAll")
        decoded("grøn")
        assertGeometryPreserved(geometry)
        capture("Wide cold image — actual 160×90 cover and full credit after decode")
        capture("Wide cold image — actual 160×90 image in 80pt row", row: true)
    }

    func testValidLocalImagesDecodeAndRedrawWithoutMappingReads() {
        launch("localReady")
        decoded("grøn")
        let geometry = checkFrames(), reads = count("offlineImage.reads"), starts = count("offlineImage.starts")
        XCTAssertGreaterThanOrEqual(reads, 1)
        for redraw in 1...3 {
            tap("offlineImage.redraw")
            waitLabel("offlineImage.redraws", "Gentegninger: \(redraw)")
            XCTAssertEqual(count("offlineImage.reads"), reads)
            XCTAssertEqual(count("offlineImage.starts"), starts)
        }
        assertGeometryPreserved(geometry)
        capture("Ready image — unchanged local cover and credit")
        capture("Ready image — unchanged local favorite thumbnail", row: true)
    }

    func testInvalidLocalImageCanBeReplacedWithoutChangingArticle() {
        launch("replacement")
        waitLabel("offlineImage.coverState", "Cover: Fejl: ugyldig lokal fil")
        waitLabel("offlineImage.rowState", "Række: Fejl: ugyldig lokal fil")
        XCTAssertEqual(count("offlineImage.decoded"), 0)
        let coverFailure = app.descendants(matching: .any).matching(identifier: "articleImage.coverFailure").firstMatch
        let rowFailure = app.descendants(matching: .any).matching(identifier: "articleImage.favoriteFailure").firstMatch
        XCTAssertTrue(coverFailure.waitForExistence(timeout: 5))
        XCTAssertTrue(rowFailure.waitForExistence(timeout: 5))
        XCTAssertEqual(coverFailure.label, "Billedet kunne ikke vises")
        XCTAssertEqual(rowFailure.label, "Billedet kunne ikke vises")
        for unsupportedDiagnosis in ["Tjek din internetforbindelse", "Medie offline"] {
            XCTAssertFalse(app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", unsupportedDiagnosis)).firstMatch.exists,
                "A corrupt local image does not establish a network diagnosis")
        }
        let geometry = checkFrames()
        capture("Invalid image — actual loader failure keeps cover and credit")
        capture("Invalid image — neutral icon-only 80pt row with accessible failure label", row: true)
        tap("offlineImage.replace")
        decoded("blå")
        XCTAssertFalse(coverFailure.exists)
        XCTAssertFalse(rowFailure.exists)
        assertGeometryPreserved(geometry)
        capture("Replaced image — same article and revision decode new blue cover")
        capture("Replaced image — same article and revision decode new blue thumbnail", row: true)
    }

    func testReturnedAccountCannotDisplayOriginalHeldResult() {
        launch("accountRoundTrip")
        waitCount("offlineImage.reads", atLeast: 1)
        XCTAssertEqual(count("offlineImage.starts"), 0)
        let geometry = checkFrames()
        tap("offlineImage.roundTrip")
        waitLabel("offlineImage.owner", "Ny A-generation")
        waitLabel("offlineImage.coverState", "Cover: Klargør")
        waitLabel("offlineImage.rowState", "Række: Klargør")
        tap("offlineImage.releaseOne")
        // The serial worker has moved beyond the original read. The new lease's
        // lookup remains physically held, so any loaded event would be stale.
        waitCount("offlineImage.reads", atLeast: 2)
        XCTAssertEqual(count("offlineImage.starts"), 0)
        XCTAssertEqual(count("offlineImage.decoded"), 0)
        capture("Returned account — old lookup cannot show an image")
        tap("offlineImage.releaseAll")
        decoded("blå")
        assertGeometryPreserved(geometry)
        capture("Returned account — current lease decoded blue cover")
        capture("Returned account — current lease decoded blue thumbnail", row: true)
    }

    func testOnlineImageIgnoresUnrelatedCacheEviction() {
        launch("onlineUnrelatedEviction")
        decoded("magenta fallback")
        let baseline = settledOnlineCounters()
        let geometry = checkFrames(online: true)
        tap("offlineImage.evictUnrelated")
        waitLabel("offlineImage.cacheEpoch", "Ny uvedkommende cache-epoke")
        waitLabel("offlineImage.redraws", "Gentegninger: 1")
        // Observe past the asynchronous cache notification and SwiftUI updates;
        // a single immediate snapshot could miss a later reload regression.
        let unwanted = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let self else { return true }
            return baseline.contains { self.count($0.key) != $0.value }
        }, object: nil)
        unwanted.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unwanted], timeout: 1.5), .completed)
        decoded("magenta fallback")
        assertGeometryPreserved(geometry, online: true)
        capture("Online input — original local magenta cover survives unrelated eviction")
        capture("Online input — original local magenta row survives unrelated eviction", row: true)
    }

    /// Sample actual screen pixels over time; callback times describe lifecycle,
    /// not presentation opacity or a claim of 60fps/physical-device smoothness.
    private func captureWarmReentrySeries(_ name: String) {
        var samples: [[String: Any]] = []
        for index in 0..<16 {
            let started = ProcessInfo.processInfo.systemUptime
            let screen = XCUIScreen.main.screenshot()
            let finished = ProcessInfo.processInfo.systemUptime
            let attachment = XCTAttachment(screenshot: screen)
            attachment.name = "\(name) frame \(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            samples.append(["index": index, "startedUptime": started, "finishedUptime": finished])
            Thread.sleep(forTimeInterval: 0.08)
        }
        let payload: [String: Any] = ["samples": samples, "actualFixture": report(),
            "limits": "Sampled original screenshots and lifecycle times, not an opacity/FPS measurement"]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = name + " timing and lifecycle"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testWarmCoverNavigationAndRecreationSamples() {
        launch("warmReentry")
        decoded("grøn")
        let warm = count("offlineImage.decoded")
        let baseline = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        baseline.name = "Warm original favorite and Home card before navigation"
        baseline.lifetime = .keepAlways; add(baseline)
        tap("offlineImage.navigateAway")
        captureWarmReentrySeries("Warm covers return from local article")
        XCTAssertFalse(app.staticTexts["offlineImage.reentryDestination"].exists)
        waitCount("offlineImage.decoded", atLeast: warm + 2)
        let returned = count("offlineImage.decoded")
        tap("offlineImage.recreate")
        captureWarmReentrySeries("Warm same-URL covers after view reconstruction")
        waitCount("offlineImage.decoded", atLeast: returned + 2)
        XCTAssertEqual(report()["imageInstance"] as? Int, 1)
        XCTAssertEqual(count("offlineImage.mainReads"), 0)
        XCTAssertEqual(count("offlineImage.fallback"), 0)
        waitLabel("offlineImage.firebase", "Firebase: ikke startet")
    }
}
