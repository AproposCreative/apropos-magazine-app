import XCTest
import UIKit

/// Visual source material for editable Figma designs. Every launch stays inside
/// the existing local smoke boundary; these are not service/device acceptances.
final class FigmaReferenceCaptureTests: XCTestCase {
    private let app = XCUIApplication()
    private var originalOrientation: UIDeviceOrientation = .unknown

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = originalOrientation
    }
    private func launch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-AproposSmokeTesting"] + arguments
        app.launch()
    }
    private func tap(_ id: String) {
        let control = app.buttons[id]
        XCTAssertTrue(control.waitForExistence(timeout: 10), id)
        for _ in 0..<5 {
            if control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.isHittable, id)
        control.tap()
    }
    private func capture(_ name: String) {
        // Retain the original, uncropped native screen. Do not erase fixture UI
        // or imply that a partial component host is a complete production page.
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Figma reference — " + name
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Figma hierarchy — " + name
        tree.lifetime = .keepAlways
        add(tree)
        var elements: [[String: Any]] = []
        func collect(_ element: any XCUIElementSnapshot) {
            let f = element.frame
            if !element.label.isEmpty && !f.isEmpty {
                elements.append(["type": element.elementType.rawValue, "identifier": element.identifier,
                    "label": element.label, "x": f.minX, "y": f.minY,
                    "width": f.width, "height": f.height])
            }
            for child in element.children { collect(child) }
        }
        if let snapshot = try? app.snapshot() { collect(snapshot) }
        if let data = try? JSONSerialization.data(withJSONObject: ["name": name,
            "screenWidth": app.frame.width, "screenHeight": app.frame.height,
            "elements": elements], options: [.sortedKeys, .prettyPrinted]) {
            let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            geometry.name = "Figma native geometry — " + name
            geometry.lifetime = .keepAlways
            add(geometry)
        }
    }

    private func waitForCaptureState(_ name: String, timeout: TimeInterval = 10,
                                     condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed { capture("DIAGNOSTIC before failed readiness — " + name) }
        XCTAssertEqual(result, .completed, name)
    }

    private func waitForMinSidePage(_ page: Int) {
        let reportElement = app.staticTexts["notifications.fixture.report"]
        waitForCaptureState("Min side settled page \(page)") {
            // StaticText may expose an empty AX value while its label carries
            // the report. Accept the first nonempty, parsable JSON dictionary.
            let report = [reportElement.value as? String, reportElement.label].compactMap { $0 }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .compactMap { raw -> [String: Any]? in
                    guard let data = raw.data(using: .utf8) else { return nil }
                    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }.first
            guard let report,
                  let paging = report["paging"] as? [String: Any],
                  let selected = paging["selectedPage"] as? Int,
                  let progress = paging["progress"] as? Double,
                  let translation = paging["dragTranslation"] as? Double,
                  let frames = report["frames"] as? [String: [String: Double]],
                  let frame = frames[page == 0 ? "minside.savedPage" : "minside.messagesPage"],
                  let x = frame["x"], let width = frame["width"] else { return false }
            return selected == page && abs(progress - Double(page)) < 0.001
                && abs(translation) < 0.5 && abs(x - self.app.frame.minX) < 1
                && abs(width - self.app.frame.width) < 1
        }
    }

    func testCleanOnboardingReferences() {
        launch(["-AproposIntroductionSmoke"])
        let status = app.staticTexts.matching(identifier: "introduction.fixture.state").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue((status.value as? String ?? "").contains("firebase=off"))
        launch(["-AproposIntroductionSmoke", "-IntroductionVisualOnly"])
        XCTAssertTrue(app.staticTexts["introduction.welcome.title"].waitForExistence(timeout: 10))
        capture("welcome · complete shared presentation")
        tap("introduction.account.google")
        tap("introduction.fixture.account.new")
        XCTAssertTrue(app.staticTexts["introduction.interests.title"].waitForExistence(timeout: 10))
        capture("interests · complete shared presentation")
        tap("introduction.interests.skip")
        XCTAssertTrue(app.staticTexts["introduction.account.title"].waitForExistence(timeout: 10))
        capture("newsletter · complete shared presentation · unchecked")
        launch(["-AproposIntroductionSmoke", "-IntroductionVisualOnly", "-IntroductionSmokeScenario", "restored"])
        XCTAssertTrue(app.staticTexts["introduction.welcome.title"].waitForExistence(timeout: 10))
        capture("restored welcome · complete shared presentation · local identity")
    }

    func testMinSideReferences() {
        launch(["-AproposNotificationInboxSmoke", "-AproposNotificationCoversSmoke"])
        let firebase = app.staticTexts["notifications.fixture.firebase"]
        XCTAssertTrue(firebase.waitForExistence(timeout: 10))
        XCTAssertEqual(firebase.label, "Firebase: ikke startet")
        XCTAssertTrue(app.buttons["minside.page.saved"].waitForExistence(timeout: 5))
        waitForMinSidePage(0)
        capture("saved · actual MinSidePages · local host without main tabs")
        tap("minside.page.messages")
        waitForMinSidePage(1)
        capture("messages · actual MinSidePages · local host without main tabs")
    }

    func testFullPlayerReferences() {
        launch(["-AproposProgressSmoke", "-AproposFullPlayerSmoke"])
        let firebase = app.staticTexts["full.player.fixture.firebase"]
        XCTAssertTrue(firebase.waitForExistence(timeout: 10))
        XCTAssertEqual(firebase.label, "Firebase: ikke startet")
        tap("full.player.fixture.open")
        XCTAssertTrue(app.staticTexts["podcast.full.category"].waitForExistence(timeout: 10))
        capture("player · actual large sheet · local artwork and playback")
        let queue = app.buttons["podcast.full.queue"]
        for _ in 0..<8 {
            if queue.exists && queue.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(queue.exists)
        XCTAssertTrue(queue.isHittable)
        queue.tap()
        XCTAssertTrue(app.navigationBars["Kø"].waitForExistence(timeout: 10))
        capture("queue · actual native sheet · local episodes")
    }

    func testPureProductPageReferences() {
        for screen in ["help", "contact", "theme", "whatsnew", "author", "series"] {
            captureProductPage(screen)
        }
    }

    func testEditorialDetailReferences() {
        for screen in ["author", "series"] {
            captureProductPage(screen, expectsArticleContent: true)
        }
    }

    func testAccountAndSettingsReferences() {
        for screen in ["settings", "account-guest", "account-create", "account-signin", "account-reset"] {
            captureProductPage(screen)
        }
    }

    func testSignedInAndNewsletterReferences() {
        for screen in ["account-signedin", "newsletter-manual"] {
            captureProductPage(screen)
        }
    }

    func testEditorialRootReferences() {
        for screen in ["home", "articles", "categories", "category-detail", "podcasts"] {
            launch(["-AproposFigmaReferenceSmoke", "-FigmaReferenceScreen", screen])
            let metadata = app.staticTexts["figma.editorial.reference.metadata"]
            XCTAssertTrue(metadata.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let report = metadata.value as? String ?? ""
                return report.contains("\"ready\":true") && report.contains("\"firebaseStarted\":false")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            if screen == "home" {
                XCTAssertTrue(app.scrollViews["home.feed"].waitForExistence(timeout: 10))
                // Require visible editorial content, not merely the outer feed
                // container, which also exists for the genuine empty state.
                waitForCaptureState("populated shared Home hero") {
                    self.app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.hero.title."))
                        .allElementsBoundByIndex.contains { element in
                            element.exists && !element.label.isEmpty && element.isHittable
                                && element.frame.intersects(self.app.frame)
                        }
                }
                XCTAssertFalse(app.staticTexts["Ingen artikler endnu"].exists)
            } else if screen == "articles" {
                XCTAssertTrue(app.buttons["search.controls.toggle"].waitForExistence(timeout: 10))
            } else if screen == "categories" {
                XCTAssertTrue(app.buttons["Anmeldelser"].waitForExistence(timeout: 10))
            } else {
                XCTAssertTrue(app.navigationBars[screen == "podcasts" ? "Lydindhold" : "Anmeldelser"].waitForExistence(timeout: 10))
            }
            capture(screen + " · actual product body and phone shell · fixed local content")
        }
    }

    func testMinSideFullPhoneChromeReferences() {
        launch(["-AproposFigmaReferenceSmoke", "-FigmaReferenceScreen", "minside"])
        XCTAssertTrue(app.buttons["minside.page.saved"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["notifications.fixture.firebase"].label, "Firebase: ikke startet")
        waitForMinSidePage(0)
        capture("saved · actual pages and phone shell · fixed local content")
        tap("minside.page.messages")
        waitForMinSidePage(1)
        capture("messages · actual pages and phone shell · fixed local content")
    }

    func testActualReaderReferences() {
        launch(["-AproposFigmaReferenceSmoke", "-FigmaReferenceScreen", "reader"])
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", "Boganmeldelse: Nogen der kender nogen")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["article.header.author"].waitForExistence(timeout: 10))
        // The real body is lower in the article. Capture the top before making
        // lazy/offscreen WebKit existence a condition of the header reference.
        capture("article-header · actual full reader · local inline excerpt")
        let paragraph = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Man kan fortælle et liv")).firstMatch
        for _ in 0..<8 {
            if paragraph.exists && paragraph.frame.intersects(app.frame.insetBy(dx: 0, dy: 140)) { break }
            app.swipeUp()
        }
        waitForCaptureState("actual WebKit public opening paragraph", timeout: 15) {
            self.app.webViews.firstMatch.exists && paragraph.exists
                && paragraph.frame.intersects(self.app.frame.insetBy(dx: 0, dy: 140))
                && !self.app.buttons["reader.bodyRetry"].exists
        }
        capture("article-body · actual full reader · local inline excerpt")
    }

    // These checks exercise the exact product presentations with an injected
    // interface locale. Editorial data remains local Danish fixture data;
    // this gallery is not evidence of an English CMS response or account SDK.
    func testEnglishSettingsAndAccountPresentations() {
        for screen in ["settings", "account-guest", "account-create", "account-signin", "account-reset"] {
            openEnglishProductPage(screen)
            if screen == "settings" {
                let language = app.buttons["settings.articleLanguage"]
                XCTAssertTrue(language.waitForExistence(timeout: 10))
                XCTAssertTrue(language.label.contains("App language"))
                // Do not select a language here: the override must leave the
                // persisted setting unchanged, whatever the owner selected.
            } else {
                assertEnglishLabel(app.textFields["account.email"], "Email")
                if screen == "account-reset" {
                    tap("Forgot password?")
                    XCTAssertTrue(app.navigationBars["Reset password"].waitForExistence(timeout: 5))
                    assertEnglishLabel(app.buttons["account.submit"], "Send reset email")
                    XCTAssertFalse(app.secureTextFields["account.password"].exists)
                } else {
                    assertEnglishLabel(app.secureTextFields["account.password"], "Password")
                    assertEnglishLabel(app.buttons["account.submit"], screen == "account-create" ? "Create account" : "Sign in")
                    if screen == "account-create" {
                        XCTAssertTrue(app.textFields["Name (optional)"].exists)
                        assertEnglishLabel(app.secureTextFields["account.confirmation"], "Confirm password")
                    } else {
                        XCTAssertTrue(app.buttons["Forgot password?"].exists)
                    }
                }
            }
            captureEnglishPresentation(screen)
        }
    }

    func testEnglishHelpContactAndThemePresentations() {
        for screen in ["help", "contact", "theme"] {
            openEnglishProductPage(screen)
            if screen == "help" {
                XCTAssertTrue(app.staticTexts["How do I save articles?"].exists)
                XCTAssertTrue(app.staticTexts["Can I read offline?"].exists)
                XCTAssertTrue(app.staticTexts["How do I change notifications?"].exists)
            } else if screen == "contact" {
                assertEnglishLabel(app.textViews["support.message"], "Your message")
                assertEnglishLabel(app.buttons["support.openDraft"], "Open email draft")
                assertEnglishLabel(app.staticTexts["support.status"],
                    "Your message is only sent when you choose Send in the email draft.")
            } else {
                for title in ["System", "Light", "Dark"] {
                    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists, title)
                }
            }
            // No mail, pasteboard or theme actions are invoked by this gallery.
            captureEnglishPresentation(screen)
        }
    }

    func testEnglishNewsletterAndWhatsNewPresentations() {
        for screen in ["account-signedin", "newsletter-manual", "whatsnew"] {
            openEnglishProductPage(screen)
            if screen == "account-signedin" {
                assertEnglishLabel(app.staticTexts["reader.account.email"], "reader@example.invalid")
                assertEnglishLabel(app.buttons["reader.account.topic.music"], "Music")
                assertEnglishLabel(app.buttons["reader.account.topic.film"], "Series & Film")
            } else if screen == "newsletter-manual" {
                assertEnglishLabel(app.staticTexts["reader.newsletter.email"], "reader@example.invalid")
                let choice = app.switches["reader.newsletter.optin"]
                assertEnglishLabel(choice, "Yes to Apropos’ newsletter")
                XCTAssertEqual(choice.value as? String, "0")
                assertEnglishLabel(app.buttons["reader.newsletter.close"], "Close")
            } else {
                XCTAssertTrue(app.staticTexts["Save with an account and choose Danish or English."].exists)
                XCTAssertTrue(app.staticTexts["Save with your account"].exists)
                XCTAssertTrue(app.staticTexts["App language"].exists)
                XCTAssertTrue(app.buttons["Continue"].exists)
            }
            // Keep the local newsletter model idle: viewing is not consent.
            captureEnglishPresentation(screen)
        }
    }

    func testEnglishIntroductionPresentations() {
        launch(["-AproposIntroductionSmoke", "-AproposInterfaceEnglishSmoke"])
        let status = app.staticTexts.matching(identifier: "introduction.fixture.state").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue((status.value as? String ?? "").contains("firebase=off"))
        launch(["-AproposIntroductionSmoke", "-IntroductionVisualOnly", "-AproposInterfaceEnglishSmoke"])
        assertEnglishLabel(app.staticTexts["introduction.welcome.title"], "Read. Listen.\nStay curious.")
        assertEnglishLabel(app.buttons["introduction.account.google"], "Continue with Google")
        captureEnglishPresentation("introduction-welcome")
        // The existing local account-choice button never opens a provider SDK.
        tap("introduction.account.google")
        tap("introduction.fixture.account.new")
        assertEnglishLabel(app.staticTexts["introduction.interests.title"], "What are you curious about?")
        assertEnglishLabel(app.buttons["introduction.topic.music"], "Music")
        assertEnglishLabel(app.buttons["introduction.topic.film"], "Series & Film")
        captureEnglishPresentation("introduction-interests")
        tap("introduction.interests.skip")
        assertEnglishLabel(app.staticTexts["introduction.account.title"], "Stories in your inbox.")
        let choice = app.descendants(matching: .any)["introduction.newsletter.choice"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertEqual(choice.value as? String, "Not selected")
        captureEnglishPresentation("introduction-newsletter-unchecked")
    }

    func testEnglishFullPlayerAndQueuePresentations() {
        launch(["-AproposProgressSmoke", "-AproposFullPlayerSmoke", "-AproposInterfaceEnglishSmoke"])
        let firebase = app.staticTexts["full.player.fixture.firebase"]
        XCTAssertTrue(firebase.waitForExistence(timeout: 10))
        XCTAssertEqual(firebase.label, "Firebase: ikke startet")
        tap("full.player.fixture.open")
        // Only the recognized MUSIK taxonomy has a translated display key;
        // unknown editorial fixture labels retain their exact source text.
        assertEnglishLabel(app.staticTexts["podcast.full.category"], "MUSIC • KULTUR • MENNESKER OG FÆLLESSKAB")
        assertEnglishLabel(app.buttons["podcast.player.playPause"], "Play")
        assertEnglishLabel(app.buttons["podcast.full.sleep"], "Sleep timer")
        captureEnglishPresentation("player-large-sheet-local-episodes")
        let queue = app.buttons["podcast.full.queue"]
        for _ in 0..<8 {
            if queue.exists && queue.isHittable { break }
            app.swipeUp()
        }
        assertEnglishLabel(queue, "Playback queue")
        XCTAssertTrue(queue.isHittable)
        queue.tap()
        XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout: 10))
        assertEnglishLabel(app.staticTexts["podcast.queue.nowPlaying"], "Playing")
        captureEnglishPresentation("queue-local-episodes")
    }

    private func assertEnglishLabel(_ element: XCUIElement, _ expected: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 {
            if element.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10), expected, file: file, line: line)
        XCTAssertEqual(element.label, expected, file: file, line: line)
    }

    private func captureEnglishPresentation(_ screen: String) {
        capture(screen + " · English interface · actual product body · local presentation data; no English CMS/provider/service acceptance")
    }

    private func referenceReport(_ element: XCUIElement) -> [String: Any]? {
        [element.value as? String, element.label].compactMap { $0 }.compactMap { raw in
            guard let data = raw.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }.first
    }

    private func openEnglishProductPage(_ screen: String) {
        launch(["-AproposFigmaReferenceSmoke", "-FigmaReferenceScreen", screen, "-AproposInterfaceEnglishSmoke"])
        let report = app.staticTexts.matching(identifier: "figma.reference.metadata").firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 10), screen)
        XCTAssertEqual(referenceReport(report)?["firebaseStarted"] as? Bool, false, screen)
        tap("figma.reference.open")
        waitForCaptureState("English actual product presentation: " + screen) {
            self.referenceReport(report)?["presented"] as? Bool == true
        }
        let titles = ["settings": "Settings", "account-guest": "Sign in or create",
            "account-create": "Create account", "account-signin": "Sign in", "account-reset": "Sign in",
            "help": "Help and support", "contact": "Contact us", "theme": "Theme",
            "account-signedin": "Your reading choices", "newsletter-manual": "Newsletter"]
        if let title = titles[screen] {
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), screen)
        } else if screen == "whatsnew" {
            XCTAssertTrue(app.staticTexts["What’s new"].waitForExistence(timeout: 10))
        }
        if ["account-signedin", "newsletter-manual"].contains(screen) {
            let local = app.staticTexts.matching(identifier: "figma.account.reference.metadata").firstMatch
            waitForCaptureState("English local account presentation ready: " + screen) {
                self.referenceReport(local)?["ready"] as? Bool == true
            }
            XCTAssertEqual(referenceReport(local)?["firebaseStarted"] as? Bool, false)
        }
    }

    private func captureProductPage(_ screen: String, expectsArticleContent: Bool = false) {
        launch(["-AproposFigmaReferenceSmoke", "-FigmaReferenceScreen", screen])
        let report = app.staticTexts.matching(identifier: "figma.reference.metadata").firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 10), screen)
        XCTAssertTrue((report.value as? String ?? report.label).contains("\"firebaseStarted\":false"), screen)
        tap("figma.reference.open")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (report.value as? String ?? "").contains("\"presented\":true")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
        let titles = ["settings": "Indstillinger", "account-guest": "Log ind eller opret",
            "account-create": "Opret konto", "account-signin": "Log ind", "account-reset": "Log ind",
            "help": "Hjælp og support", "contact": "Kontakt os", "theme": "Tema",
            "series": "Seriens navn", "account-signedin": "Dine læservalg", "newsletter-manual": "Nyhedsbrev"]
        if let title = titles[screen] {
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        } else if screen == "whatsnew" {
            XCTAssertTrue(app.staticTexts["Hvad er nyt"].waitForExistence(timeout: 10))
        } else if screen == "author" {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Frederik Kragh")).firstMatch.waitForExistence(timeout: 10))
        }
        if ["account-signedin", "newsletter-manual"].contains(screen) {
            let local = app.staticTexts.matching(identifier: "figma.account.reference.metadata").firstMatch
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (local.value as? String ?? "").contains("\"ready\":true")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        }
        if screen == "account-reset" {
            tap("Glemt adgangskode?")
            XCTAssertTrue(app.navigationBars["Nulstil adgangskode"].waitForExistence(timeout: 5))
        }
        if expectsArticleContent {
            let article = app.staticTexts.matching(NSPredicate(format: "label == %@",
                "Anmeldelse: The Terminal List, sæson 1 på Prime Video")).firstMatch
            waitForCaptureState(screen + " populated actual article list") { article.exists }
        }
        capture(screen + " · actual product body · local capture host")
    }
}
