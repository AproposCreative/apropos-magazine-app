import CoreGraphics
import XCTest

/// The actual introduction view, model and presentation with local receipts.
/// This class never starts an auth SDK, changes the system theme or supplies a
/// successful layout/state through launch arguments.
final class WelcomeLandingSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    private var title: XCUIElement { app.staticTexts["introduction.welcome.title"] }
    private var status: XCUIElement {
        app.staticTexts.matching(identifier: "introduction.fixture.state").firstMatch
    }
    private var reportElement: XCUIElement {
        app.staticTexts["introduction.welcome.fixture.report"]
    }

    private func launch(visualOnly: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposIntroductionSmoke"]
        if visualOnly { app.launchArguments.append("-IntroductionVisualOnly") }
        app.launch()
        // This identifier is present in the unchanged introduction as well.
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        capture("initial actual introduction before new landing assertions")
    }

    private func report() -> [String: Any]? {
        guard reportElement.exists, let raw = reportElement.value as? String,
              let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return value
    }

    private func capture(_ phase: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Welcome original screen — " + phase
        image.lifetime = .keepAlways; add(image)
        var frames: [String: Any] = [:]
        for id in ["introduction.welcome.logo", "introduction.language", "introduction.welcome.title",
                   "introduction.welcome.signIn", "introduction.welcome.signUp", "introduction.welcome.back"] {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            let frame = element.exists ? element.frame : .zero
            frames[id] = ["exists": element.exists, "hittable": element.exists && element.isHittable,
                          "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        let payload: [String: Any] = ["phase": phase, "frames": frames,
            "fixtureStatus": status.exists ? status.value as? String ?? "" : "",
            "welcomeReport": report() ?? [:]]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) {
            let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            receipt.name = "Welcome frames and actual fixture state — " + phase
            receipt.lifetime = .keepAlways; add(receipt)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Welcome AX — " + phase
        hierarchy.lifetime = .keepAlways; add(hierarchy)
    }

    private func waitReport(_ phase: String, condition: @escaping ([String: Any]) -> Bool) {
        let predicate = NSPredicate { [weak self] _, _ in
            guard let value = self?.report() else { return false }
            return condition(value)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: reportElement)], timeout: 8)
        capture(phase)
        XCTAssertEqual(result, .completed, phase)
    }

    private func waitStatus(_ values: [String], phase: String) {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: values.map {
            NSPredicate(format: "value CONTAINS %@", $0)
        })
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: status)], timeout: 8)
        capture(phase)
        XCTAssertEqual(result, .completed, values.joined(separator: ", "))
    }

    private func reveal(_ element: XCUIElement, in identifier: String) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            let scroller = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            guard scroller.exists else { break }
            scroller.swipeUp()
        }
    }

    private func tap(_ identifier: String, in scroller: String = "introduction.scroll") {
        let button = app.buttons[identifier]
        _ = button.waitForExistence(timeout: 3)
        // Provider choices can be below the fold; their explicit Back control
        // can then be above it after cancelling the existing email sheet.
        for _ in 0..<16 {
            if button.exists && button.isHittable { break }
            let container = app.descendants(matching: .any).matching(identifier: scroller).firstMatch
            guard container.exists else { break }
            let visible = container.frame.intersection(app.frame)
            if button.exists && !button.frame.isEmpty && button.frame.midY < visible.midY {
                container.swipeDown()
            } else { container.swipeUp() }
        }
        capture("before actual tap " + identifier)
        XCTAssertTrue(button.exists, identifier)
        XCTAssertTrue(button.isEnabled, identifier)
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }

    private func chooseLanguage(_ code: String) {
        tap("introduction.language")
        let choice = app.buttons["introduction.language." + code]
        _ = choice.waitForExistence(timeout: 5)
        capture("actual language menu before choosing " + code)
        XCTAssertTrue(choice.exists); XCTAssertTrue(choice.isHittable)
        choice.tap()
        waitReport("language " + code + " has reached the actual shared view") { $0["language"] as? String == code }
    }

    private func assertSameIntroduction(_ expected: [String: Any]) {
        guard let actual = report() else { XCTFail("Missing typed welcome fixture report"); return }
        for key in ["modelID", "revision", "step", "introductionReads", "introductionWrites",
                    "accountRequests", "newsletterRequests", "newsletterConsent", "selectedTopicIDs"] {
            guard let before = expected[key], let after = actual[key] else {
                XCTFail("Missing actual state field: " + key); continue
            }
            XCTAssertTrue(NSDictionary(dictionary: [key: before]).isEqual(to: [key: after]),
                "Changing language must preserve the actual introduction state/I/O: " + key)
        }
        XCTAssertEqual(actual["newsletterConsent"] as? Bool, false)
        XCTAssertEqual(actual["newsletterRequests"] as? Int, 0)
        XCTAssertEqual(actual["accountRequests"] as? Int, 0)
        XCTAssertEqual(actual["firebaseStarted"] as? Bool, false)
    }

    func testFirstWelcomeHasThemeAwareLogoLanguageAndTwoActions() {
        launch(visualOnly: true)
        let language = app.buttons["introduction.language"]
        _ = language.waitForExistence(timeout: 3)
        capture("first landing layout before all new UI requirements")
        let logo = app.descendants(matching: .any).matching(identifier: "introduction.welcome.logo").firstMatch
        let signIn = app.buttons["introduction.welcome.signIn"]
        let signUp = app.buttons["introduction.welcome.signUp"]
        XCTAssertTrue(language.exists)
        XCTAssertTrue(logo.exists)
        XCTAssertTrue(signIn.exists); XCTAssertTrue(signUp.exists)
        let isAccessibilitySize = report()?["dynamicTypeIsAccessibilitySize"] as? Bool ?? false
        for button in [language, signIn, signUp] {
            if isAccessibilitySize {
                reveal(button, in: "introduction.scroll")
                capture("accessibility landing control revealed " + button.identifier)
            }
            XCTAssertTrue(button.isHittable, button.identifier)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, button.identifier)
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.5, button.identifier)
            if !isAccessibilitySize {
                XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(button.frame),
                    "Both first-screen actions and the language control must initially fit at normal text size")
            }
        }
        let named: [(String, XCUIElement)] = [("logo", logo), ("language", language), ("headline", title),
            ("signIn", signIn), ("signUp", signUp)]
        capture("actual landing layout before non-overlap assertions")
        for (index, first) in named.enumerated() {
            XCTAssertGreaterThan(first.1.frame.width, 0, first.0)
            XCTAssertGreaterThan(first.1.frame.height, 0, first.0)
            for second in named.dropFirst(index + 1) {
                let overlap = first.1.frame.intersection(second.1.frame)
                XCTAssertFalse(!overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5,
                    first.0 + " must not overlap " + second.0)
            }
        }
        XCTAssertLessThanOrEqual(signIn.frame.maxY, signUp.frame.minY + 0.5)
    }

    func testLanguageMenuChangesDanishEnglishDanishWithoutRestartingOrConsenting() {
        launch()
        _ = reportElement.waitForExistence(timeout: 5)
        capture("actual baseline before language-state assertions")
        guard let baseline = report() else { XCTFail("Missing typed welcome fixture report"); return }
        XCTAssertEqual(baseline["language"] as? String, "da")
        XCTAssertEqual(baseline["step"] as? String, "welcome")
        XCTAssertNotNil((baseline["modelID"] as? String).flatMap(UUID.init(uuidString:)))
        XCTAssertNotNil((baseline["revision"] as? String).flatMap(UUID.init(uuidString:)))
        assertSameIntroduction(baseline)
        let danishTitle = title.label
        chooseLanguage("en")
        capture("English UI from the actual language choice before translation assertions")
        XCTAssertEqual(app.buttons["introduction.welcome.signIn"].label, "Sign in")
        XCTAssertEqual(app.buttons["introduction.welcome.signUp"].label, "Create account")
        XCTAssertNotEqual(title.label, danishTitle)
        assertSameIntroduction(baseline)
        chooseLanguage("da")
        capture("Danish restored without model or consent changes")
        XCTAssertEqual(app.buttons["introduction.welcome.signIn"].label, "Log ind")
        XCTAssertEqual(app.buttons["introduction.welcome.signUp"].label, "Opret konto")
        XCTAssertEqual(title.label, danishTitle)
        assertSameIntroduction(baseline)
    }

    func testLandingActionsKeepExistingEmailCancellationAndGoogleNewReaderFlow() {
        launch()
        tap("introduction.welcome.signIn")
        tap("introduction.account.emailSignIn")
        _ = app.staticTexts["introduction.fixture.account"].waitForExistence(timeout: 5)
        capture("existing sign-in form reached through the first landing action")
        XCTAssertTrue(app.staticTexts["introduction.fixture.account"].exists)
        reveal(app.staticTexts["introduction.fixture.account.mode"], in: "introduction.fixture.account.form")
        capture("email sign-in mode before route assertions")
        XCTAssertEqual(app.staticTexts["introduction.fixture.account.mode"].label, "Log ind med e-mail")
        XCTAssertFalse(app.secureTextFields["account.confirmation"].exists)
        waitStatus(["step=welcome", "provider=emailSignIn", "accountRequests=1", "acceptedLogins=0", "newsletterRequests=0"],
            phase: "email operation owns the unchanged welcome until an actual receipt")
        tap("introduction.fixture.destination.close", in: "introduction.fixture.account.form")
        waitStatus(["step=welcome", "sheet=none", "awaiting=0", "acceptedLogins=0", "completed=0"],
            phase: "cancelling email returns to the same provider choice")
        tap("introduction.welcome.back")
        tap("introduction.welcome.signUp")
        tap("introduction.account.google")
        waitStatus(["provider=google", "accountRequests=2", "sheet=account", "acceptedLogins=0"],
            phase: "signup keeps the existing explicit Google operation")
        tap("introduction.fixture.account.new", in: "introduction.fixture.account.form")
        waitStatus(["step=interests", "sheet=none", "awaiting=0", "acceptedLogins=1", "newUser=1", "completed=0", "newsletterRequests=0"],
            phase: "the actual local new-reader receipt reaches interests without early completion")
        tap("introduction.interests.skip")
        let choice = app.descendants(matching: .any).matching(identifier: "introduction.newsletter.choice").firstMatch
        reveal(choice, in: "introduction.scroll")
        capture("existing newsletter step before unchecked-consent assertions")
        XCTAssertTrue(choice.exists)
        XCTAssertEqual(choice.value as? String, "Ikke valgt")
        waitStatus(["step=account", "completed=0", "newsletterRequests=0", "newsletterConsent=0"],
            phase: "the unchanged newsletter choice remains explicit and unchecked")
    }
    func testLandscapeKeepsTheLandingAndBothActionsReachable() {
        launch(visualOnly: true)
        guard let baseline = report() else { XCTFail("Missing typed welcome fixture report"); return }
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation == .unknown ? .portrait : originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { [weak self] _, _ in
            guard let frame = self?.app.frame else { return false }
            return frame.width > frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 8), .completed)
        let screen = XCUIScreen.main.screenshot()
        let original = XCTAttachment(screenshot: screen)
        original.name = "Welcome original screen — actual landscape before reachability checks"
        original.lifetime = .keepAlways; add(original)
        XCTAssertGreaterThan(screen.image.size.width, screen.image.size.height,
            "A cropped portrait application screenshot cannot prove actual landscape")
        capture("actual landscape before controls are revealed")
        for identifier in ["introduction.language", "introduction.welcome.signIn", "introduction.welcome.signUp"] {
            let control = app.buttons[identifier]
            reveal(control, in: "introduction.scroll")
            capture("actual landscape revealed " + identifier)
            XCTAssertTrue(control.exists); XCTAssertTrue(control.isEnabled); XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 43.5)
            XCTAssertGreaterThanOrEqual(control.frame.height, 43.5)
        }
        assertSameIntroduction(baseline)
    }

    func testProviderBackAndReplayRestoreTheInitialSystemAppearance() {
        launch()
        guard let baseline = report(), let expected = baseline["colorScheme"] as? String else {
            XCTFail("Missing actual initial appearance"); return
        }
        capture("initial presenting appearance before opening the dark provider choice")
        tap("introduction.welcome.signIn")
        waitReport("actual provider chooser remains dark") { $0["colorScheme"] as? String == "dark" }
        tap("introduction.welcome.back")
        waitReport("returning to the actual landing restores its initial presenting appearance") {
            $0["colorScheme"] as? String == expected
        }
        XCTAssertTrue(app.buttons["introduction.welcome.signIn"].exists)
        XCTAssertTrue(app.buttons["introduction.welcome.signUp"].exists)
        assertSameIntroduction(baseline)
        tap("introduction.skip")
        waitStatus(["cover=0", "completed=1", "accountRequests=0", "newsletterRequests=0"],
            phase: "explicit guest completion keeps account and newsletter untouched")
        tap("introduction.fixture.replay", in: "introduction.fixture.home")
        waitReport("replayed landing restores the same presenting appearance") {
            $0["colorScheme"] as? String == expected && $0["step"] as? String == "welcome"
        }
        XCTAssertTrue(app.buttons["introduction.welcome.signIn"].exists)
        XCTAssertTrue(app.buttons["introduction.welcome.signUp"].exists)
        XCTAssertEqual(report()?["newsletterConsent"] as? Bool, false)
        XCTAssertEqual(report()?["newsletterRequests"] as? Int, 0)
        XCTAssertEqual(report()?["accountRequests"] as? Int, 0)
    }

}
