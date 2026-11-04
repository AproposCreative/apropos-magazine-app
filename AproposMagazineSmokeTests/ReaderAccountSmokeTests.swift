import CoreGraphics
import XCTest

/// The real account route/setup, committed states and captured button actions.
/// Manual transports never configure an SDK or claim real login/mail delivery.
final class ReaderAccountSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRank = 0
    private enum Row: Int, CaseIterable {
        case firebase, accountA, accountB, guest, pending, reply, failRead, refreshPreferences, hold, held, release, writes, failSave,
             verifications, replyVerification, email, sendVerification, refresh, verificationMessage, verified,
             interestsError, retry, design, music, film, newsletter, message, save, later, guestMessage
        var id: String {
            switch self {
            case .firebase: return "reader.fixture.firebase"
            case .accountA: return "reader.fixture.accountA"
            case .accountB: return "reader.fixture.accountB"
            case .guest: return "reader.fixture.guest"
            case .pending: return "reader.fixture.pending"
            case .reply: return "reader.fixture.reply"
            case .failRead: return "reader.fixture.failRead"
            case .refreshPreferences: return "reader.fixture.refreshPreferences"
            case .hold: return "reader.fixture.hold"
            case .held: return "reader.fixture.held"
            case .release: return "reader.fixture.release"
            case .writes: return "reader.fixture.writes"
            case .failSave: return "reader.fixture.failSave"
            case .verifications: return "reader.fixture.verifications"
            case .replyVerification: return "reader.fixture.replyVerification"
            case .email: return "reader.account.email"
            case .sendVerification: return "reader.account.verification.send"
            case .refresh: return "reader.account.verification.refresh"
            case .verificationMessage: return "reader.account.verification.message"
            case .verified: return "reader.account.verification.verified"
            case .interestsError: return "reader.account.interests.error"
            case .retry: return "reader.account.interests.retry"
            case .design: return "reader.account.topic.design"
            case .music: return "reader.account.topic.music"
            case .film: return "reader.account.topic.film"
            case .newsletter: return "reader.account.newsletter"
            case .message: return "reader.account.message"
            case .save: return "reader.account.save"
            case .later: return "reader.account.later"
            case .guestMessage: return "reader.account.guest"
            }
        }
        var isButton: Bool {
            switch self {
            case .accountA, .accountB, .guest, .reply, .failRead, .refreshPreferences, .release, .failSave, .replyVerification,
                 .sendVerification, .refresh, .retry, .design, .music, .film, .newsletter, .save, .later: return true
            default: return false
            }
        }
    }
    override func setUpWithError() throws {
        continueAfterFailure = false; lastRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderAccountSmoke"]
        if name.contains("LargestText") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let open = app.buttons["reader.fixture.open"]
        let entryList = app.collectionViews.firstMatch
        XCTAssertTrue(entryList.waitForExistence(timeout: 10))
        // At accessibility text sizes, the fixture's explanatory paragraph
        // pushes the entry below the fold; navigate it like a reader would.
        for _ in 0..<5 {
            if open.exists && open.isHittable { break }
            entryList.swipeUp()
        }
        XCTAssertTrue(open.waitForExistence(timeout: 10)); XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        assertLabel(.firebase, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app.terminate(); app = nil }
    private var form: XCUIElement { app.descendants(matching: .any).matching(identifier: "reader.account.form").firstMatch }
    private func element(_ row: Row) -> XCUIElement {
        if row == .hold { return app.switches[row.id] }
        return row.isButton ? app.buttons[row.id] : app.staticTexts[row.id]
    }
    private func control(_ row: Row) -> XCUIElement {
        let item = element(row)
        guard row == .hold else { return item }
        // SwiftUI's switch row includes its label. As in the history smoke,
        // reveal and tap the actual native control rather than the row center.
        let knob = item.switches.firstMatch
        return knob.exists ? knob : item
    }
    private var viewport: CGRect {
        let appFrame = app.frame
        let scroller = form.frame.intersection(appFrame)
        let navigationBar = app.navigationBars.firstMatch
        let navBottom = navigationBar.exists ? navigationBar.frame.maxY : appFrame.minY + 110
        let top = max(scroller.minY, navBottom) + 8
        let bottom = min(scroller.maxY, appFrame.maxY - 36) - 8
        return CGRect(x: scroller.minX + 12, y: top, width: max(1, scroller.width - 24), height: max(1, bottom - top))
    }
    private func scroll(up: Bool, in frame: CGRect) {
        let distance = min(300, max(100, frame.height * 0.42))
        let startY = up ? frame.midY + distance / 2 : frame.midY - distance / 2
        let endY = up ? frame.midY - distance / 2 : frame.midY + distance / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.midX, dy: startY)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: endY)))
    }
    private func anchor(in bounds: CGRect) -> Int {
        let candidates = Row.allCases.compactMap { row -> (CGFloat, Int)? in
            let item = control(row)
            guard item.exists else { return nil }
            let frame = item.frame
            guard !frame.isEmpty else { return nil }
            let visible = frame.intersection(bounds)
            guard !visible.isNull, visible.height > 0 else { return nil }
            return (abs(visible.midY - bounds.midY), row.rawValue)
        }
        return candidates.min(by: { $0.0 < $1.0 })?.1 ?? lastRank
    }
    @discardableResult
    private func reveal(_ row: Row, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        for _ in 0..<28 {
            // One geometry sample per iteration. Re-reading the Form/navigation
            // hierarchy for every possible anchor adds hundreds of AX queries.
            let bounds = viewport
            let item = control(row)
            if item.exists {
                let frame = item.frame
                if !frame.isEmpty, frame.midY.isFinite {
                    if item.isHittable && bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                        lastRank = row.rawValue; return item
                    }
                    scroll(up: frame.midY >= bounds.minY, in: bounds)
                    continue
                }
            }
            scroll(up: row.rawValue >= anchor(in: bounds), in: bounds)
        }
        XCTFail("Account row outside visible viewport: \(row.id)", file: file, line: line)
        return control(row)
    }
    private func tap(_ row: Row, file: StaticString = #filePath, line: UInt = #line) {
        let item = reveal(row, file: file, line: line)
        XCTAssertTrue(item.waitForExistence(timeout: 5), file: file, line: line)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 4), .completed, file: file, line: line)
        XCTAssertTrue(item.isHittable, file: file, line: line)
        let bounds = viewport, frame = item.frame
        XCTAssertTrue(bounds.contains(CGPoint(x: frame.midX, y: frame.midY)), file: file, line: line)
        item.tap()
    }
    private func assertLabel(_ row: Row, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(row, file: file, line: line)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element(row))
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 4), .completed, file: file, line: line)
    }
    private func assertChoice(_ row: Row, _ selected: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let item = reveal(row, file: file, line: line)
        XCTAssertTrue(item.isEnabled, file: file, line: line)
        XCTAssertEqual(item.value as? String, selected ? "Valgt" : "Ikke valgt", file: file, line: line)
    }
    private func loadA() {
        tap(.accountA); assertLabel(.pending, "Ventende svar: A"); tap(.reply)
        assertLabel(.email, "a@example.test"); assertChoice(.design, true); assertChoice(.music, false)
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = title + " — AX"; tree.lifetime = .keepAlways; add(tree)
        for id in ["reader.newsletter.fixture.report", "reader.fixture.newsletter.report"] {
            let element = app.staticTexts[id]
            if element.exists, let data = element.label.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                receipt.name = title + " — " + id; receipt.lifetime = .keepAlways; add(receipt)
            }
        }
    }

    func testRemoteRefreshUpdatesCleanSelectionWithoutSaving() {
        loadA(); assertChoice(.film, false)
        tap(.refreshPreferences); assertLabel(.pending, "Ventende svar: A")
        assertChoice(.design, true); assertChoice(.film, false)
        tap(.reply); assertChoice(.design, true); assertChoice(.film, true); assertChoice(.music, false)
        capture("Interesser — friske servervalg vises uden automatisk gemning")
        assertLabel(.writes, "Gemninger: 0")
    }

    func testRemoteRefreshPreservesLocalAddAndRemovalInActualForm() {
        loadA(); tap(.design); tap(.music)
        assertChoice(.design, false); assertChoice(.music, true)
        tap(.refreshPreferences); assertLabel(.pending, "Ventende svar: A")
        tap(.reply)
        assertChoice(.design, false); assertChoice(.music, true); assertChoice(.film, true)
        capture("Interesser — lokal musik og fravalgt design bevares sammen med ny film")
        assertLabel(.writes, "Gemninger: 0")
        tap(.save)
        let saved = app.alerts["Dine valg er gemt"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.buttons["Færdig"].tap()
        XCTAssertTrue(app.buttons["reader.fixture.open"].waitForExistence(timeout: 5))
    }

    func testOriginalSaveButtonActionCannotWriteForTheNextAccount() {
        assertLabel(.guestMessage, "Du kan læse magasinet uden en konto.")
        loadA(); tap(.music); assertChoice(.music, true)
        tap(.hold); XCTAssertEqual(element(.hold).value as? String, "1")
        tap(.save); assertLabel(.held, "Handlinger: 1 venter · 0 afsluttet")
        tap(.accountB); assertLabel(.pending, "Ventende svar: B"); tap(.reply)
        assertLabel(.email, "b@example.test"); assertChoice(.design, false); assertChoice(.music, true)
        tap(.release); assertLabel(.held, "Handlinger: 0 venter · 1 afsluttet"); assertLabel(.writes, "Gemninger: 0")
        XCTAssertFalse(app.alerts["Dine valg er gemt"].exists)
        assertLabel(.email, "b@example.test"); assertChoice(.design, false); assertChoice(.music, true)
        capture("Konto — B beholder egne interesser, og A-handlingen udfører ingen gemning")
    }

    func testRealSetupRetryAndSaveFailurePreserveDraftUntilAcknowledgedSuccess() {
        tap(.accountA); assertLabel(.pending, "Ventende svar: A"); tap(.failRead)
        assertLabel(.interestsError, "Kunne ikke hente dine interesser. Prøv igen, når du er online.")
        reveal(.design); XCTAssertFalse(element(.design).isEnabled)
        tap(.retry); assertLabel(.pending, "Ventende svar: A"); tap(.reply)
        assertChoice(.design, true); tap(.music); assertChoice(.music, true)
        tap(.failSave); tap(.save)
        assertLabel(.interestsError, "Gemning er ikke bekræftet. Dine valg kan blive synkroniseret, når forbindelsen vender tilbage. Prøv igen for at bekræfte dem.")
        assertChoice(.design, true); assertChoice(.music, true)
        capture("Konto — gemmefejl bevarer de aktuelle interesser i formularen")
        tap(.save)
        let saved = app.alerts["Dine valg er gemt"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.buttons["Færdig"].isHittable)
        capture("Konto — kvittering efter den lokale transports faktiske svar")
        saved.buttons["Færdig"].tap()
        XCTAssertTrue(app.buttons["reader.fixture.open"].waitForExistence(timeout: 5))
    }

    func testLateVerificationAndNewsletterPresentationStayWithTheirOriginalOwner() {
        loadA(); tap(.sendVerification); assertLabel(.verifications, "Bekræftelser: 1 venter · 0 afsluttet")
        tap(.accountB); assertLabel(.pending, "Ventende svar: B"); tap(.reply)
        tap(.replyVerification); assertLabel(.verifications, "Bekræftelser: 0 venter · 1 afsluttet")
        assertLabel(.email, "b@example.test"); XCTAssertFalse(element(.verificationMessage).exists)
        tap(.newsletter)
        let email = app.staticTexts["reader.newsletter.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5)); XCTAssertEqual(email.label, "b@example.test")
        capture("Konto — den faktiske nyhedsbrevsformular bruger kun den aktuelle e-mail")
        app.buttons["reader.newsletter.close"].tap()
        tap(.guest); assertLabel(.guestMessage, "Du kan læse magasinet uden en konto.")
        XCTAssertFalse(element(.email).exists); XCTAssertFalse(element(.verificationMessage).exists)
        assertLabel(.firebase, "Firebase: ikke startet")
        capture("Konto — gæstelæsning uden tidligere e-mail eller verifikationsstatus")
    }

    private var newsletterForm: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "reader.newsletter.form").firstMatch
    }

    private func newsletterReport() throws -> [String: Any] {
        let local = app.staticTexts["reader.newsletter.fixture.report"]
        let element = local.exists ? local : app.staticTexts["reader.fixture.newsletter.report"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let data = try XCTUnwrap(element.label.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func waitNewsletter(_ phase: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 8)
        if result != .completed { capture("Nyhedsbrev — afventning fejlede: " + phase) }
        XCTAssertEqual(result, .completed, phase)
    }

    @discardableResult
    private func revealNewsletter(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<20 {
            let frame = newsletterForm.frame.intersection(app.frame)
            let navbar = app.navigationBars["Nyhedsbrev"]
            let top = max(frame.minY, navbar.exists ? navbar.frame.maxY : frame.minY) + 8
            // The injected reply panel is a fixture-only inset. UIKit still
            // reports Form rows behind it as hittable, so reveal above it.
            let footer = app.staticTexts["Kun lokale svar · intet netværk"]
            let bottom = min(frame.maxY, footer.exists ? footer.frame.minY - 16 : frame.maxY)
            let bounds = CGRect(x: frame.minX + 12, y: top, width: max(1, frame.width - 24),
                                height: max(1, bottom - top - 12))
            if element.exists {
                let target = element.frame
                if element.isHittable && bounds.contains(CGPoint(x: target.midX, y: target.midY)) { return element }
                scroll(up: target.midY >= bounds.minY, in: bounds)
            } else { scroll(up: true, in: bounds) }
        }
        capture("Nyhedsbrev — kontrol uden for synligt område")
        XCTFail("Actual newsletter control must be reachable in its native Form")
        return element
    }

    private func tapNewsletter(_ element: XCUIElement) {
        let target = revealNewsletter(element)
        XCTAssertTrue(target.isEnabled)
        XCTAssertTrue(target.isHittable)
        if target.elementType == .switch {
            let knob = target.switches.firstMatch
            (knob.exists ? knob : target).tap()
        } else { target.tap() }
    }

    private func tapNewsletterReply(_ id: String) {
        let button = app.buttons[id]
        waitNewsletter("local transport control " + id) { button.exists && button.isEnabled && button.isHittable }
        button.tap()
    }

    @discardableResult
    private func revealSupplementalAccountControl(_ id: String) -> XCUIElement {
        let item = app.descendants(matching: .any).matching(identifier: id).firstMatch
        for _ in 0..<20 {
            let bounds = viewport
            if item.exists, item.isHittable, bounds.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) { return item }
            scroll(up: true, in: bounds)
        }
        capture("Konto — ekstra lokal kontrol ikke synlig: " + id)
        XCTFail("Expected local account control " + id)
        return item
    }

    private func openVerifiedNewsletterForA() throws {
        loadA()
        tap(.refresh)
        reveal(.verified)
        XCTAssertTrue(element(.verified).exists)
        tap(.newsletter)
        XCTAssertTrue(newsletterForm.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["reader.newsletter.email"].label, "a@example.test")
        let report = try newsletterReport()
        XCTAssertEqual(report["canonicalUID"] as? String, "A")
        XCTAssertEqual(report["canonicalEmailVerified"] as? Bool, true)
        XCTAssertEqual(report["firebaseStarted"] as? Bool, false)
    }

    func testNativeNewsletterRequiresConsentAndConfirmsSameRequestAfterRetry() throws {
        try openVerifiedNewsletterForA()
        let choice = app.switches["reader.newsletter.optin"]
        XCTAssertTrue(choice.exists)
        XCTAssertEqual(choice.value as? String, "0")
        XCTAssertEqual((try newsletterReport()["requests"] as? [[String: Any]])?.count, 0)
        XCTAssertFalse(app.staticTexts["reader.newsletter.status"].exists)
        capture("Nyhedsbrev — faktisk formular er umarkeret og har ingen tilmelding")
        app.buttons["reader.newsletter.close"].tap()
        XCTAssertFalse(newsletterForm.exists)
        tap(.newsletter)
        XCTAssertTrue(newsletterForm.waitForExistence(timeout: 5))
        XCTAssertEqual(choice.value as? String, "0")
        XCTAssertEqual((try newsletterReport()["requests"] as? [[String: Any]])?.count, 0)
        tapNewsletter(choice)
        waitNewsletter("one explicit opt-in waits for its held real-model response") {
            guard let report = try? self.newsletterReport() else { return false }
            return report["status"] as? String == "submitting"
                && (report["requests"] as? [[String: Any]])?.count == 1
                && report["pendingReplies"] as? Int == 1
        }
        let first = try XCTUnwrap((newsletterReport()["requests"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["expectedUserID"] as? String, "A")
        XCTAssertEqual(first["expectedEmail"] as? String, "a@example.test")
        XCTAssertEqual(first["consent"] as? Bool, true)
        XCTAssertEqual(first["consentVersion"] as? String, "apropos-newsletter-v1")
        XCTAssertEqual(first["source"] as? String, "ios-onboarding")
        XCTAssertFalse(app.buttons["reader.newsletter.retry"].exists)
        capture("Nyhedsbrev — afventer svar og påstår endnu ingen tilmelding")
        tapNewsletterReply("reader.newsletter.fixture.pending")
        waitNewsletter("unknown server outcome is pending, not subscribed") {
            (try? self.newsletterReport()["status"] as? String) == "pending"
        }
        let status = revealNewsletter(app.staticTexts["reader.newsletter.status"])
        XCTAssertTrue(status.label.contains("endnu ikke bekræftet"))
        capture("Nyhedsbrev — afventende kvittering har synligt genforsøg")
        tapNewsletter(app.buttons["reader.newsletter.retry"])
        waitNewsletter("retry re-enters held send") {
            guard let report = try? self.newsletterReport() else { return false }
            return report["status"] as? String == "submitting"
                && (report["requests"] as? [[String: Any]])?.count == 2
                && report["pendingReplies"] as? Int == 1
        }
        let requests = try XCTUnwrap(newsletterReport()["requests"] as? [[String: Any]])
        XCTAssertEqual(requests[0] as NSDictionary, requests[1] as NSDictionary)
        tapNewsletterReply("reader.newsletter.fixture.success")
        waitNewsletter("matching authoritative receipt confirms signup") {
            (try? self.newsletterReport()["status"] as? String) == "subscribed"
        }
        XCTAssertEqual(revealNewsletter(app.staticTexts["reader.newsletter.status"]).label,
                       "Du er tilmeldt Apropos’ nyhedsbrev.")
        XCTAssertFalse(app.buttons["reader.newsletter.retry"].exists)
        let final = try newsletterReport()
        XCTAssertEqual(final["requestID"] as? String, first["requestID"] as? String)
        XCTAssertEqual(final["completedResponses"] as? Int, 2)
        XCTAssertEqual(final["pendingReplies"] as? Int, 0)
        XCTAssertEqual(final["firebaseStarted"] as? Bool, false)
        capture("Nyhedsbrev — samme samtykke og request får først succes efter korrekt svar")
        app.buttons["reader.newsletter.close"].tap()
        assertLabel(.writes, "Gemninger: 0")
        assertLabel(.firebase, "Firebase: ikke startet")
    }

    func testManualNewsletterReconfirmationUsesSamePrimaryActionAndFreshChoiceAfterSpentToken() throws {
        try openVerifiedNewsletterForA()
        tapNewsletter(app.switches["reader.newsletter.optin"])
        waitNewsletter("first explicit request reaches held transport") { (try? self.newsletterReport()["pendingReplies"] as? Int) == 1 }
        let first = try XCTUnwrap((newsletterReport()["requests"] as? [[String: Any]])?.first)
        XCTAssertTrue(first["reconfirmationChallenge"] is NSNull)
        tapNewsletterReply("reader.newsletter.fixture.challenge")
        let reconfirm = app.buttons["reader.newsletter.reconfirm"]
        waitNewsletter("challenge waits for explicit Tilmeld igen") {
            (try? self.newsletterReport()["status"] as? String) == "reconfirmationRequired"
        }
        // Form materializes rows lazily. At AX5 the explanatory section fills
        // the viewport; reveal the real row before asking whether it exists.
        XCTAssertTrue(revealNewsletter(reconfirm).isEnabled)
        XCTAssertEqual(revealNewsletter(reconfirm).label, "Tilmeld igen")
        XCTAssertEqual((try newsletterReport()["requests"] as? [[String: Any]])?.count, 1)
        capture("Nyhedsbrev — samme formular og eksplicit Tilmeld igen uden popup")
        tapNewsletter(reconfirm)
        waitNewsletter("second explicit tap sends same request with challenge") { (try? self.newsletterReport()["pendingReplies"] as? Int) == 1 }
        let second = try XCTUnwrap((newsletterReport()["requests"] as? [[String: Any]])?.last)
        XCTAssertEqual(second["requestID"] as? String, first["requestID"] as? String)
        XCTAssertEqual(second["reconfirmationChallenge"] as? String, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        tapNewsletterReply("reader.newsletter.fixture.spentChallenge")
        let choice = app.switches["reader.newsletter.optin"]
        waitNewsletter("spent challenge exposes a fresh unchecked choice without another request") {
            guard let report = try? self.newsletterReport() else { return false }
            return report["status"] as? String == "reconfirmationRequired"
                && report["pendingReplies"] as? Int == 0
        }
        XCTAssertTrue(revealNewsletter(choice).isEnabled)
        XCTAssertEqual(revealNewsletter(choice).value as? String, "0")
        XCTAssertEqual((try newsletterReport()["requests"] as? [[String: Any]])?.count, 2)
        XCTAssertFalse(reconfirm.exists)
        capture("Nyhedsbrev — brugt bekræftelse genopretter kun et umarkeret valg")
        tapNewsletter(choice)
        waitNewsletter("new explicit choice creates a new request") { (try? self.newsletterReport()["requests"] as? [[String: Any]])?.count == 3 }
        let fresh = try XCTUnwrap((newsletterReport()["requests"] as? [[String: Any]])?.last)
        XCTAssertNotEqual(fresh["requestID"] as? String, first["requestID"] as? String)
        XCTAssertTrue(fresh["reconfirmationChallenge"] is NSNull)
        tapNewsletterReply("reader.newsletter.fixture.success")
        waitNewsletter("matching new receipt confirms only the new choice") { (try? self.newsletterReport()["status"] as? String) == "subscribed" }
        XCTAssertEqual(try newsletterReport()["firebaseStarted"] as? Bool, false)
    }

    func testNativeNewsletterAccountChangeRejectsHeldSuccessLargestText() throws {
        try openVerifiedNewsletterForA()
        XCTAssertEqual(try newsletterReport()["systemAccessibility"] as? Bool, true)
        XCTAssertEqual(try newsletterReport()["systemTextCategory"] as? String,
                       "UICTContentSizeCategoryAccessibilityXXXL")
        tapNewsletter(app.switches["reader.newsletter.optin"])
        waitNewsletter("A owns the only pending opt-in") {
            (try? self.newsletterReport()["pendingReplies"] as? Int) == 1
        }
        let original = try XCTUnwrap((newsletterReport()["requests"] as? [[String: Any]])?.first)
        capture("Nyhedsbrev — A afventer lokalt svar ved største tekst")
        tapNewsletterReply("reader.newsletter.fixture.accountB")
        waitNewsletter("canonical account change dismisses A's actual form") { !self.newsletterForm.exists }
        assertLabel(.pending, "Ventende svar: B"); tap(.reply)
        assertLabel(.email, "b@example.test")
        let lateReply = revealSupplementalAccountControl("reader.fixture.newsletter.lateSuccess")
        XCTAssertTrue(lateReply.isEnabled); lateReply.tap()
        _ = revealSupplementalAccountControl("reader.fixture.newsletter.report")
        waitNewsletter("late A success drains without a B subscription") {
            guard let report = try? self.newsletterReport() else { return false }
            return report["completedResponses"] as? Int == 1
                && report["pendingReplies"] as? Int == 0 && report["status"] as? String == "idle"
        }
        let discarded = try newsletterReport()
        XCTAssertEqual(discarded["canonicalUID"] as? String, "B")
        XCTAssertEqual(discarded["canonicalEmail"] as? String, "b@example.test")
        XCTAssertEqual(discarded["requestID"] as? String, "")
        let requests = try XCTUnwrap(discarded["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0] as NSDictionary, original as NSDictionary)
        XCTAssertEqual(requests[0]["expectedUserID"] as? String, "A")
        XCTAssertFalse(app.staticTexts["reader.newsletter.status"].exists)
        capture("Nyhedsbrev — sen A-kvittering kan ikke blive til B-samtykke")
        tap(.newsletter)
        XCTAssertTrue(newsletterForm.waitForExistence(timeout: 5))
        XCTAssertEqual(revealNewsletter(app.staticTexts["reader.newsletter.email"]).label, "b@example.test")
        let choice = revealNewsletter(app.switches["reader.newsletter.optin"])
        XCTAssertEqual(choice.value as? String, "0")
        XCTAssertFalse(app.staticTexts["reader.newsletter.status"].exists)
        XCTAssertEqual((try newsletterReport()["requests"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(try newsletterReport()["firebaseStarted"] as? Bool, false)
        capture("Nyhedsbrev — B ser egen e-mail og et nyt umarkeret valg")
        app.buttons["reader.newsletter.close"].tap()
        assertLabel(.writes, "Gemninger: 0")
        assertLabel(.firebase, "Firebase: ikke startet")
    }
}
