import CoreGraphics
import XCTest

/// Shared production introduction/store/presentation seam with local transports.
/// Real email UI and local provider receipts; no SDK login or network calls.
final class IntroductionSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private var status: XCUIElement {
        app.staticTexts.matching(identifier: "introduction.fixture.state").firstMatch
    }

    private func launch(_ scenario: String = "first") {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposIntroductionSmoke", "-IntroductionSmokeScenario", scenario]
        app.launch()
        let firstContent = scenario == "corrupt" ? "introduction.storage.error" : "introduction.welcome.title"
        XCTAssertTrue(app.staticTexts[firstContent].waitForExistence(timeout: 10))
        waitStatus(["firebase=off", scenario == "restored-active" ? "completed=1" : "completed=0", "step=welcome", "cover=1", "sheet=none", "awaiting=0"])
    }

    private func waitStatus(_ values: [String], file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: values.map {
            NSPredicate(format: "value CONTAINS %@", $0)
        })
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, file: file, line: line)
    }

    @discardableResult
    private func reveal(_ item: XCUIElement, in identifier: String = "introduction.scroll", file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let scroller: XCUIElement
        if app.scrollViews[identifier].exists { scroller = app.scrollViews[identifier] }
        else if app.collectionViews[identifier].exists { scroller = app.collectionViews[identifier] }
        else if app.tables[identifier].exists { scroller = app.tables[identifier] }
        else { scroller = app.descendants(matching: .any)[identifier].firstMatch }
        XCTAssertTrue(scroller.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<24 {
            var frame = scroller.frame.intersection(app.frame)
            if identifier == "introduction.scroll" {
                let controls = app.buttons["introduction.fixture.controls"]
                if controls.exists {
                    // SwiftUI reports the full window for this scroll view,
                    // including content hidden behind its fixed fixture inset.
                    let top = max(frame.minY, controls.frame.maxY + 12)
                    frame = CGRect(x: frame.minX, y: top, width: frame.width,
                        height: max(1, frame.maxY - top))
                }
            }
            let bounds = CGRect(x: frame.minX + 12, y: frame.minY + 12,
                width: max(1, frame.width - 24), height: max(1, frame.height - 28))
            var down = true
            if item.exists {
                let target = item.frame
                if !target.isEmpty, target.midY.isFinite {
                    if bounds.contains(CGPoint(x: target.midX, y: target.midY)), item.isHittable { return item }
                    down = target.midY >= bounds.midY
                }
            }
            let distance = min(360, bounds.height * 0.6)
            let start = down ? bounds.midY + distance / 2 : bounds.midY - distance / 2
            let end = down ? bounds.midY - distance / 2 : bounds.midY + distance / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: bounds.midX, dy: start)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: end)))
        }
        XCTFail("Introduction control outside viewport: \(item.identifier)", file: file, line: line)
        return item
    }

    private func tap(_ identifier: String, in scroller: String = "introduction.scroll", file: StaticString = #filePath, line: UInt = #line) {
        let control = identifier == "introduction.newsletter.choice"
            ? app.descendants(matching: .any)[identifier].firstMatch : app.buttons[identifier]
        let item = reveal(control, in: scroller, file: file, line: line)
        XCTAssertTrue(item.isEnabled, file: file, line: line)
        XCTAssertTrue(item.isHittable, file: file, line: line)
        item.tap()
    }

    private func fixtureAction(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu = app.buttons["introduction.fixture.controls"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(menu.isHittable, file: file, line: line)
        menu.tap()
        let action = app.buttons[identifier]
        XCTAssertTrue(action.waitForExistence(timeout: 5), file: file, line: line)
        var menuBeforeScrolling: String?
        for _ in 0..<10 {
            if action.isHittable { break }
            if menuBeforeScrolling == nil { menuBeforeScrolling = app.debugDescription }
            // UIKit's popup may use the system accessibility text size even
            // when its fixture-only trigger is compact. Reveal inside that
            // popup, never by dragging the introduction behind it.
            let queries = [app.scrollViews, app.collectionViews, app.tables, app.descendants(matching: .menu)]
            let candidates = queries.flatMap {
                $0.containing(.button, identifier: identifier).allElementsBoundByIndex
            }.filter {
                $0.exists && $0.identifier != "introduction.scroll" && $0.identifier != "introduction.fixture.home"
            }
            let containers = candidates.compactMap { candidate -> (XCUIElement, CGRect)? in
                let bounds = candidate.frame.intersection(app.frame).insetBy(dx: 12, dy: 16)
                guard !bounds.isNull, bounds.width > 44, bounds.height > 80 else { return nil }
                return (candidate, bounds)
            }
            guard let (container, _) = containers.min(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else { break }
            // On iOS 26.5 the popup collection reports its full content height,
            // beyond the clipped visible menu. Coordinate drags from that frame
            // can start on the backdrop and dismiss it. Native element gestures
            // instead resolve actual hit points in two visible menu rows.
            let rows = container.descendants(matching: .button)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "introduction.fixture."))
                .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
                .sorted { $0.frame.midY < $1.frame.midY }
            guard let top = rows.first, let bottom = rows.last,
                  top.identifier != bottom.identifier else { break }
            let target = action.frame
            let middle = (top.frame.midY + bottom.frame.midY) / 2
            let down = target.isEmpty || !target.midY.isFinite || target.midY >= middle
            if down { bottom.press(forDuration: 0.05, thenDragTo: top) }
            else { top.press(forDuration: 0.05, thenDragTo: bottom) }
        }
        if !action.isHittable {
            if let menuBeforeScrolling {
                let before = XCTAttachment(string: menuBeforeScrolling)
                before.name = "Testdata — popup hierarchy before any scroll: \(identifier)"
                before.lifetime = .keepAlways
                add(before)
            }
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "Testdata — native menu unavailable or target still outside its viewport: \(identifier)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(action.isHittable, file: file, line: line)
        guard action.isHittable else { return }
        action.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func showAccountChoice(_ provider: String) {
        guard !app.buttons["introduction.account." + provider].exists else { return }
        if app.buttons["introduction.welcome.back"].exists { tap("introduction.welcome.back") }
        tap(provider == "emailSignIn" ? "introduction.welcome.signIn" : "introduction.welcome.signUp")
    }

    private func openAccount(_ provider: String) {
        showAccountChoice(provider)
        tap("introduction.account." + provider)
        XCTAssertTrue(app.staticTexts["introduction.fixture.account"].waitForExistence(timeout: 8))
        waitStatus(["cover=1", "sheet=account", "awaiting=0", "provider=" + provider])
    }

    private func cancelAccount() {
        let close = app.buttons["introduction.fixture.destination.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.staticTexts["introduction.welcome.title"].waitForExistence(timeout: 5))
        waitStatus(["cover=1", "sheet=none", "awaiting=0", "step=welcome"])
    }

    private func chooseNewUser(_ provider: String = "google") {
        openAccount(provider)
        tap("introduction.fixture.account.new", in: "introduction.fixture.account.form")
        waitStatus(["cover=1", "sheet=none", "awaiting=0", "step=interests", "newUser=1"])
    }

    private var newsletterChoice: XCUIElement {
        app.descendants(matching: .any)["introduction.newsletter.choice"].firstMatch
    }

    func testRecoveryStopClosesIntroductionAndRejectsOldDraftAndReplay() {
        launch("recovery")
        chooseNewUser()
        tap("introduction.topic.design")
        waitStatus(["selected=design", "cover=1", "recoveryClosed=0"])
        let original = status.value as? String ?? ""
        let writeToken = original.split(separator: " ").first { $0.hasPrefix("introWrites=") }
        XCTAssertNotNil(writeToken)
        capture("Introduktion — original draft før lokalt stop")
        fixtureAction("introduction.fixture.stop")
        waitStatus(["recoveryClosed=1", "cover=0", "sheet=none", "awaiting=0", String(writeToken ?? "introWrites=missing")])
        XCTAssertTrue(app.staticTexts["introduction.fixture.magazine"].waitForExistence(timeout: 5))
        tap("introduction.fixture.oldAction", in: "introduction.fixture.home")
        waitStatus(["oldActionsRejected=1", "cover=0", "sheet=none", "awaiting=0", String(writeToken ?? "introWrites=missing")])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        waitStatus(["recoveryClosed=1", "cover=0", "sheet=none", "awaiting=0", String(writeToken ?? "introWrites=missing")])
        XCTAssertFalse(app.staticTexts["introduction.welcome.title"].exists)
        capture("Introduktion — lukket draft og afvist gammelt replay")
    }

    func testFirstLaunchCanSkipAndReplayWithoutAccountOrNewsletterConsent() {
        launch()
        for provider in ["apple", "google", "emailSignUp", "emailSignIn"] {
            showAccountChoice(provider)
            XCTAssertTrue(reveal(app.buttons["introduction.account." + provider]).isEnabled)
        }
        tap("introduction.welcome.back")
        XCTAssertFalse(app.descendants(matching: .any)["introduction.step"].firstMatch.exists)
        capture("Introduktion — direkte Apple, Google, e-mail og gæsteadgang")
        reveal(app.buttons["introduction.skip"])
        capture("Introduktion — magasinpille før gæsteadgang")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Magasinpille — synlighed før tryk"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        tap("introduction.skip")
        waitStatus(["completed=1", "preferenceWrites=0", "cover=0", "sheet=none", "awaiting=0",
            "accountRequests=0", "newsletterRequests=0", "newsletterConfirmed=0"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        XCTAssertTrue(app.staticTexts["introduction.welcome.title"].waitForExistence(timeout: 5))
        waitStatus(["completed=1", "step=welcome", "cover=1", "preferenceWrites=0"])
        openAccount("apple")
        cancelAccount()
        tap("introduction.skip")
        waitStatus(["completed=1", "preferenceWrites=0", "cover=0", "acceptedLogins=0", "newsletterRequests=0"])
    }

    func testCorruptStorageCanBeDeferredWithoutClaimingCompletionAndReopensWithTheError() {
        launch("corrupt")
        waitStatus(["loaded=0", "completed=0", "introWrites=0", "preferenceWrites=0"])
        for action in ["introduction.welcome.signIn", "introduction.welcome.signUp"] {
            XCTAssertTrue(app.buttons[action].exists)
            XCTAssertFalse(app.buttons[action].isEnabled)
        }
        XCTAssertFalse(app.buttons["introduction.account.google"].exists, "Providers are not mounted before the disabled landing actions can open them")
        tap("introduction.storage.retry")
        XCTAssertTrue(app.staticTexts["introduction.storage.error"].exists)
        waitStatus(["loaded=0", "completed=0", "introWrites=0", "cover=1", "awaiting=0"])
        reveal(app.buttons["introduction.storage.defer"])
        capture("Introduktion — lagerfejl kan udsættes uden falsk gennemførelse")
        tap("introduction.storage.defer")
        waitStatus(["loaded=0", "completed=0", "introWrites=0", "preferenceWrites=0", "deferrals=1",
            "cover=0", "sheet=none", "awaiting=0", "accountRequests=0", "newsletterRequests=0"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        XCTAssertTrue(app.staticTexts["introduction.storage.error"].waitForExistence(timeout: 5))
        waitStatus(["loaded=0", "completed=0", "introWrites=0", "cover=1", "deferrals=1"])
        tap("introduction.storage.defer")
        waitStatus(["completed=0", "introWrites=0", "deferrals=2", "cover=0", "sheet=none", "awaiting=0"])
    }

    func testLateTopicsAndPersistedDraftResumeAndFailedSavesStayRetryable() {
        launch("late")
        chooseNewUser()
        XCTAssertTrue(app.descendants(matching: .any)["introduction.topics.loading"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["introduction.topic.design"].exists)
        fixtureAction("introduction.fixture.topics.fail")
        XCTAssertTrue(app.staticTexts["introduction.topics.error"].waitForExistence(timeout: 5))
        tap("introduction.topics.retry")
        tap("introduction.topic.design")
        waitStatus(["selected=design", "preferenceWrites=0"])
        fixtureAction("introduction.fixture.resume")
        waitStatus(["resumed=1", "step=interests", "selected=design", "preferenceWrites=0"])
        XCTAssertEqual(reveal(app.buttons["introduction.topic.design"]).value as? String, "Valgt")
        capture("Introduktion — store emneord og genoptaget valg")
        fixtureAction("introduction.fixture.preferences.fail")
        tap("introduction.interests.continue")
        XCTAssertTrue(app.staticTexts["introduction.interests.storage.error"].waitForExistence(timeout: 5))
        waitStatus(["step=interests", "preferenceWrites=0", "completed=0", "cover=1"])
        tap("introduction.interests.storage.retry")
        XCTAssertTrue(app.staticTexts["introduction.account.title"].waitForExistence(timeout: 5))
        waitStatus(["step=account", "saved=design", "preferenceWrites=1", "completed=0"])
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        capture("Introduktion — frivilligt nyhedsbrev efter oprettelse")
        fixtureAction("introduction.fixture.intro.fail")
        tap("introduction.finish")
        XCTAssertTrue(app.staticTexts["introduction.storage.error"].waitForExistence(timeout: 5))
        waitStatus(["completed=0", "cover=1", "sheet=none", "awaiting=0"])
        tap("introduction.storage.retry")
        waitStatus(["completed=1", "saved=design", "preferenceWrites=1", "cover=0", "newsletterRequests=0"])
    }

    func testNewGoogleSignupRequiresExplicitNewsletterChoiceAndRetriesSameRequest() {
        launch("newsletter-retry")
        chooseNewUser()
        tap("introduction.topic.design")
        tap("introduction.interests.continue")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        waitStatus(["newsletterRequests=0", "newsletterConsent=0", "completed=0"])
        tap("introduction.newsletter.choice")
        tap("introduction.back")
        tap("introduction.interests.continue")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Valgt")
        tap("introduction.finish")
        XCTAssertTrue(app.staticTexts["introduction.newsletter.status"].waitForExistence(timeout: 5))
        waitStatus(["cover=1", "completed=0", "newsletterRequests=1", "newsletterStatus=unavailable",
            "newsletterConsent=1", "newsletterSource=ios-onboarding", "newsletterVersion=apropos-newsletter-v1"])
        capture("Introduktion — en tilmelding er ikke bekræftet før kvitteringen")
        tap("introduction.newsletter.retry")
        waitStatus(["completed=1", "cover=0", "newsletterRequests=2", "newsletterConfirmed=1", "newsletterRequestStable=1"])
    }

    private func openManualExistingNewsletter(_ scenario: String) {
        launch(scenario)
        tap("introduction.skip"); waitStatus(["cover=0", "completed=1"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        openAccount("google")
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        waitStatus(["step=interests", "selected=culture", "saved=culture", "awaitingSavedInterests=0"])
        tap("introduction.interests.skip")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        waitStatus(["step=account", "preferenceWrites=0", "newsletterRequests=0"])
    }

    func testOnboardingPriorUnsubscribeRequiresExplicitInlineReconfirmation() {
        openManualExistingNewsletter("newsletter-reconfirmation")
        tap("introduction.newsletter.choice"); tap("introduction.finish")
        XCTAssertTrue(app.buttons["introduction.newsletter.reconfirm"].waitForExistence(timeout: 8))
        waitStatus(["firebase=off", "cover=1", "step=account", "newsletterRequests=1",
                    "newsletterStatus=reconfirmationRequired", "newsletterChallengeSent=0", "newsletterConfirmed=0"])
        XCTAssertEqual(reveal(app.buttons["introduction.newsletter.reconfirm"]).label, "Tilmeld igen")
        capture("Nyhedsbrev — afmeldt adresse afventer eksplicit Tilmeld igen i samme formular")
        tap("introduction.newsletter.reconfirm")
        waitStatus(["cover=0", "newsletterRequests=2", "newsletterChallengeSent=1",
                    "newsletterConfirmed=1", "newsletterRequestStable=1", "preferenceWrites=0", "saved=culture"])
    }

    func testOnboardingSpentChallengeReturnsUncheckedChoiceAndNeedsNewExplicitRequest() {
        openManualExistingNewsletter("newsletter-reconfirmation-expired")
        tap("introduction.newsletter.choice"); tap("introduction.finish")
        XCTAssertTrue(app.buttons["introduction.newsletter.reconfirm"].waitForExistence(timeout: 8))
        tap("introduction.newsletter.reconfirm")
        waitStatus(["cover=1", "newsletterRequests=2", "newsletterStatus=reconfirmationRequired", "newsletterConfirmed=0"])
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        XCTAssertTrue(reveal(newsletterChoice).isEnabled)
        XCTAssertFalse(app.buttons["introduction.newsletter.reconfirm"].exists)
        capture("Nyhedsbrev — udløbet bekræftelse kræver et nyt umarkeret valg uden automatisk genforsøg")
        tap("introduction.newsletter.choice"); tap("introduction.finish")
        XCTAssertTrue(app.buttons["introduction.newsletter.reconfirm"].waitForExistence(timeout: 8))
        waitStatus(["newsletterRequests=3", "newsletterChallengeSent=0", "newsletterRequestStable=0"])
        tap("introduction.newsletter.reconfirm")
        waitStatus(["cover=0", "newsletterRequests=4", "newsletterChallengeSent=1", "newsletterConfirmed=1", "preferenceWrites=0"])
    }

    func testManualReplayExistingGoogleKeepsSavedInterestsAndUncheckedNewsletterWithoutWrites() {
        launch()
        tap("introduction.skip")
        waitStatus(["cover=0", "completed=1", "preferenceWrites=0"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        openAccount("google")
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        waitStatus(["firebase=off", "cover=1", "sheet=none", "awaiting=0", "step=interests",
                    "newUser=0", "completed=1", "selected=culture", "saved=culture",
                    "awaitingSavedInterests=0", "preferenceWrites=0", "newsletterRequests=0"])
        XCTAssertTrue(reveal(app.buttons["introduction.topic.culture"]).isEnabled)
        XCTAssertEqual(reveal(app.buttons["introduction.topic.culture"]).value as? String, "Valgt")
        capture("Manuelt replay — eksisterende Google-konto og egne gemte interesser")
        tap("introduction.interests.skip")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        waitStatus(["step=account", "saved=culture", "preferenceWrites=0", "newsletterRequests=0", "newsletterConsent=0"])
        capture("Manuelt replay — fravalg ændrer ikke interesser eller nyhedsbrevssamtykke")
        tap("introduction.finish")
        waitStatus(["cover=0", "completed=1", "saved=culture", "preferenceWrites=0", "newsletterRequests=0"])
    }

    func testManualReplayWaitingForSavedInterestsAllowsSkipAndRejectsLateSeed() {
        launch("manual-preferences-loading")
        tap("introduction.skip")
        waitStatus(["cover=0", "completed=1"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        openAccount("google")
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        waitStatus(["step=interests", "awaitingSavedInterests=1", "preferencesLoading=1", "preferenceWrites=0"])
        XCTAssertFalse(reveal(app.buttons["introduction.interests.continue"]).isEnabled)
        XCTAssertTrue(reveal(app.buttons["introduction.interests.skip"]).isEnabled)
        XCTAssertTrue(reveal(app.buttons["introduction.back"]).isEnabled)
        capture("Manuelt replay — kun Fortsæt venter på egne gemte interesser")
        tap("introduction.interests.skip")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        fixtureAction("introduction.fixture.preferences.release")
        waitStatus(["step=account", "awaitingSavedInterests=0", "preferencesLoading=0", "saved=culture", "selected= ", "preferenceWrites=0", "newsletterRequests=0"])
        tap("introduction.finish")
        waitStatus(["cover=0", "saved=culture", "preferenceWrites=0", "newsletterRequests=0"])
    }

    func testManualReplaySavedInterestReadErrorHasUsableInlineRetry() {
        launch("preferences-retry")
        tap("introduction.skip")
        waitStatus(["cover=0", "completed=1"])
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        openAccount("google")
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        XCTAssertTrue(app.staticTexts["introduction.interests.saved.error"].waitForExistence(timeout: 8))
        XCTAssertFalse(reveal(app.buttons["introduction.interests.continue"]).isEnabled)
        XCTAssertTrue(reveal(app.buttons["introduction.interests.saved.retry"]).isEnabled)
        capture("Manuelt replay — gemte interesser har synlig læsefejl og aktiv Prøv igen")
        tap("introduction.interests.saved.retry")
        waitStatus(["preferenceReads=2", "preferencesLoading=0", "awaitingSavedInterests=1"])
        XCTAssertTrue(app.staticTexts["introduction.interests.saved.error"].waitForExistence(timeout: 8))
        tap("introduction.interests.saved.retry")
        waitStatus(["step=interests", "selected=culture", "saved=culture", "awaitingSavedInterests=0", "preferenceWrites=0"])
        tap("introduction.interests.skip")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
    }

    func testAppleAndEmailEntriesAreExplicitAndCancellationKeepsWelcome() {
        launch()
        openAccount("apple")
        waitStatus(["accountRequests=1", "accountVisits=1", "providerActivations=1", "acceptedLogins=0"])
        cancelAccount()
        openAccount("emailSignUp")
        XCTAssertEqual(reveal(app.staticTexts["introduction.fixture.account.mode"],
            in: "introduction.fixture.account.form").label, "Opret med e-mail")
        XCTAssertTrue(reveal(app.secureTextFields["account.confirmation"], in: "introduction.fixture.account.form").exists)
        capture("Introduktion — e-mailoprettelse med rigtig native formular")
        cancelAccount()
        openAccount("emailSignIn")
        XCTAssertEqual(reveal(app.staticTexts["introduction.fixture.account.mode"],
            in: "introduction.fixture.account.form").label, "Log ind med e-mail")
        XCTAssertFalse(app.secureTextFields["account.confirmation"].exists)
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        waitStatus(["completed=1", "cover=0", "sheet=none", "acceptedLogins=1", "newUser=0",
            "saved=culture", "preferenceWrites=0", "newsletterRequests=0"])
    }

    func testNewsletterChoiceCannotCrossAccountGenerationOrGuestCompletion() {
        launch()
        chooseNewUser()
        tap("introduction.interests.skip")
        tap("introduction.newsletter.choice")
        XCTAssertEqual(newsletterChoice.value as? String, "Valgt")
        fixtureAction("introduction.fixture.generation")
        waitStatus(["generationChanges=1", "step=welcome", "completed=0", "newsletterRequests=0"])
        chooseNewUser("apple")
        tap("introduction.interests.skip")
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
        tap("introduction.finish")
        waitStatus(["completed=1", "cover=0", "sheet=none", "acceptedLogins=2", "newsletterRequests=0", "newsletterConfirmed=0"])
    }

    func testReturningLoginStorageFailureClosesEmailAndRetryFinishesIntroduction() {
        launch()
        fixtureAction("introduction.fixture.intro.fail")
        openAccount("emailSignIn")
        tap("introduction.fixture.account.existing", in: "introduction.fixture.account.form")
        XCTAssertTrue(app.staticTexts["introduction.storage.error"].waitForExistence(timeout: 5))
        waitStatus(["completed=0", "cover=1", "sheet=none", "acceptedLogins=1", "newUser=0", "saved=culture", "preferenceWrites=0"])
        tap("introduction.storage.retry")
        waitStatus(["completed=1", "cover=0", "sheet=none", "awaiting=0", "newsletterRequests=0"])
    }

    func testRestoredAccountAndLegacyDraftStartAtAccountChoiceAndReplayDoesToo() {
        launch("restored-active")
        XCTAssertTrue(reveal(app.staticTexts["introduction.account.current"]).label.contains("reader@example.invalid"))
        XCTAssertFalse(app.staticTexts["introduction.interests.title"].exists)
        capture("Introduktion — gemt konto vises før interesser")
        tap("introduction.account.continue")
        waitStatus(["step=interests", "selected=culture", "preferenceWrites=0"])
        tap("introduction.back")
        tap("introduction.skip")
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        waitStatus(["step=welcome", "cover=1", "completed=1", "preferenceWrites=0"])
        tap("introduction.account.signOut")
        waitStatus(["step=welcome", "generationChanges=1", "cover=1"])
        for provider in ["apple", "google", "emailSignUp", "emailSignIn"] {
            showAccountChoice(provider)
            XCTAssertTrue(reveal(app.buttons["introduction.account." + provider]).isEnabled)
        }
        tap("introduction.welcome.back")
        openAccount("emailSignIn")
        cancelAccount()
    }

    func testInterestSaveWaitsForActualInitialReadBeforeWriting() {
        launch("preferences-loading")
        chooseNewUser()
        tap("introduction.topic.design")
        tap("introduction.interests.continue")
        waitStatus(["preferencesLoading=1", "preferenceReads=1", "preferenceWrites=0", "step=interests"])
        XCTAssertFalse(app.buttons["introduction.interests.continue"].isEnabled)
        XCTAssertFalse(app.staticTexts["introduction.interests.storage.error"].exists)
        fixtureAction("introduction.fixture.preferences.release")
        waitStatus(["preferencesLoading=0", "preferenceReads=1", "preferenceWrites=1", "saved=design", "step=account"])
    }

    func testFailedSignOutKeepsAccountChoiceAndVisibleRetry() {
        launch("restored-signout-failure")
        tap("introduction.account.signOut")
        waitStatus(["step=welcome", "cover=1", "generationChanges=1", "preferenceWrites=0"])
        XCTAssertTrue(app.staticTexts["introduction.account.signOut.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app.staticTexts["introduction.account.current"]).label.contains("reader@example.invalid"))
        tap("introduction.account.signOut")
        waitStatus(["step=welcome", "cover=1", "generationChanges=2"])
        showAccountChoice("google")
        XCTAssertTrue(reveal(app.buttons["introduction.account.google"]).isEnabled)
        XCTAssertFalse(app.staticTexts["introduction.account.signOut.error"].exists)
    }

    func testInterestRetryActuallyReloadsAfterReadFailureAndPreservesChoices() {
        launch("preferences-retry")
        chooseNewUser()
        tap("introduction.topic.design")
        tap("introduction.interests.continue")
        XCTAssertTrue(app.staticTexts["introduction.interests.storage.error"].waitForExistence(timeout: 5))
        waitStatus(["preferenceReads=2", "preferenceWrites=0", "step=interests", "selected=design"])
        tap("introduction.interests.storage.retry")
        waitStatus(["preferenceReads=3", "preferenceWrites=1", "saved=design", "step=account"])
        XCTAssertEqual(reveal(newsletterChoice).value as? String, "Ikke valgt")
    }
}
