import XCTest

/// Shipped view/gestures with local actions, no AVPlayer or service setup.
final class PlayerMotionSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private var originalSystemMotion: Bool?
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposProgressSmoke", "-AproposMiniMotionSmoke"]
        app.launch()
        XCTAssertTrue(app.staticTexts["mini.fixture.firebase"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mini.fixture.firebase"].label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws {
        defer { app.terminate(); app = nil }
        if let originalSystemMotion { try setSystemMotion(originalSystemMotion) }
    }

    func testPlayerActionsAndDismissWithNormalMotion() { exercise(reduced: false) }
    func testPlayerActionsAndDismissWithReducedMotion() { exercise(reduced: true) }

    func testActualSystemReducedMotionWithoutFixtureOverride() throws {
        let control = try motionSwitch()
        originalSystemMotion = try switchIsOn(control)
        try setSystemMotion(true)
        app.activate()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Systembevægelse: reduceret"),
            object: app.staticTexts["mini.fixture.systemMotion"])], timeout: 5), .completed)
        // No local override is enabled. The shipped view reads the actual environment.
        exercise(reduced: false)
    }

    private func exercise(reduced: Bool) {
        if reduced {
            let toggle = app.switches["mini.fixture.reduced"]
            (toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle).tap()
        }
        let player = app.descendants(matching: .any).matching(identifier: "podcast.mini.surface").firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        for id in ["podcast.mini.title", "podcast.mini.subtitle"] {
            let label = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(label.exists)
            XCTAssertGreaterThanOrEqual(label.frame.minY, player.frame.minY)
            XCTAssertLessThanOrEqual(label.frame.maxY, player.frame.maxY, "Text must stay inside the player at the actual text size")
        }
        app.buttons["podcast.mini.playPause"].tap()
        XCTAssertEqual(app.buttons["podcast.mini.playPause"].label, "Pause")
        XCTAssertFalse(app.staticTexts["mini.fixture.opened"].exists, "Play/pause must not open the sheet")
        app.buttons["podcast.mini.forward"].tap()
        XCTAssertEqual(app.staticTexts["mini.fixture.forwardCount"].label, "Spol frem: 1")
        XCTAssertFalse(app.staticTexts["mini.fixture.opened"].exists, "Skip must not open the sheet")
        // A short downward drag must return to its original location, not close.
        let initialY = player.frame.minY
        let start = player.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 24)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(app.staticTexts["mini.fixture.visible"].label, "Afspiller synlig")
        XCTAssertEqual(player.frame.minY, initialY, accuracy: 1)
        XCTAssertEqual(app.staticTexts["mini.fixture.openCount"].label, "Åbninger: 0", "A drag must not also activate the title button")
        XCTAssertFalse(app.staticTexts["mini.fixture.opened"].exists)
        capture(reduced ? "Mini-player — reduceret bevægelse" : "Mini-player — normal bevægelse")
        app.buttons["podcast.mini.title"].tap()
        XCTAssertTrue(app.staticTexts["mini.fixture.opened"].waitForExistence(timeout: 5))
        app.buttons["mini.fixture.closeSheet"].tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mini.fixture.openCount"].label, "Åbninger: 1")
        player.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["mini.fixture.opened"].waitForExistence(timeout: 5), "Artwork must retain the full-player touch action")
        app.buttons["mini.fixture.closeSheet"].tap()
        XCTAssertEqual(app.staticTexts["mini.fixture.openCount"].label, "Åbninger: 2")
        let dismissStart = player.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        dismissStart.press(forDuration: 0.1, thenDragTo: dismissStart.withOffset(CGVector(dx: 0, dy: 110)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(app.staticTexts["mini.fixture.visible"].label, "Afspiller lukket")
        XCTAssertEqual(app.staticTexts["mini.fixture.openCount"].label, "Åbninger: 2")
        XCTAssertFalse(app.staticTexts["mini.fixture.opened"].exists)
        app.buttons["mini.fixture.restore"].tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertEqual(player.frame.minY, initialY, accuracy: 1)
        XCTAssertEqual(app.staticTexts["mini.fixture.firebase"].label, "Firebase: ikke startet")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private enum SettingsFailure: Error { case unknownSwitchValue, settingsHierarchy }
    private func attachSettings(name: String) {
        let attachment = XCTAttachment(string: settings.debugDescription)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func switchIsOn(_ control: XCUIElement) throws -> Bool {
        switch control.value as? String {
        case "1": return true
        case "0": return false
        default: attachSettings(name: "Unknown system motion switch value"); throw SettingsFailure.unknownSwitchValue
        }
    }
    private func setSystemMotion(_ enabled: Bool) throws {
        let control = try motionSwitch()
        if try switchIsOn(control) != enabled {
            // iOS 27 exposes the label and switch as one 330pt AX element;
            // its center is text. Tap the observed trailing switch track.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let predicate = NSPredicate(format: "value == %@", enabled ? "1" : "0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: control)], timeout: 5), .completed)
        let attachment = XCTAttachment(screenshot: settings.screenshot())
        attachment.name = "Actual Settings Reduce Motion — \(enabled ? "on" : "off")"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func motionSwitch() throws -> XCUIElement {
        settings.activate()
        let control = settings.switches.matching(NSPredicate(format: "label IN %@", ["Reduce Motion", "Reducer bevægelse"])).firstMatch
        // If navigation fails, capture the real hierarchy and stop. Do not infer
        // that a preference changed from a launch argument or an unknown switch.
        if control.waitForExistence(timeout: 1) { return control }
        for _ in 0..<5 {
            let motion = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Motion", "Bevægelse"])).firstMatch
            if motion.exists && motion.isHittable {
                motion.tap()
                if control.waitForExistence(timeout: 2) { return control }
            }
            let accessibility = settings.staticTexts.matching(NSPredicate(format: "label IN %@", ["Accessibility", "Tilgængelighed"])).firstMatch
            if accessibility.exists && accessibility.isHittable { accessibility.tap(); continue }
            let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@",
                ["Back", "Tilbage", "Settings", "Indstillinger", "Accessibility", "Tilgængelighed"])).firstMatch
            if back.exists && back.isHittable { back.tap(); continue }
            settings.swipeUp()
        }
        attachSettings(name: "Inspect actual Settings hierarchy before adjusting selectors")
        throw SettingsFailure.settingsHierarchy
    }
}
