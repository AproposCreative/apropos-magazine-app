import XCTest

/// Rendered motion acceptance on the existing local smoke simulator.
/// Settings labels must be checked against the first captured hierarchy; no
/// undocumented settings URL, preference-domain write or environment override.
final class IntroductionBackdropCaptureTests: XCTestCase {
    private enum CaptureFailure: Error { case settingsHierarchy, unknownSwitchValue, control(String) }
    private let app = XCUIApplication()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private var originalReduceMotion: Bool?
    private var records: [[String: Any]] = []

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        defer { app.terminate() }
        if let originalReduceMotion { try setReduceMotion(originalReduceMotion) }
    }

    func testNativeBackdropMovesAndSystemReducedMotionPreservesPhaseAcrossSteps() throws {
        // Capture and restore the simulator's actual setting, not a fixture flag.
        let original = try motionSwitch()
        originalReduceMotion = try switchIsOn(original)
        try setReduceMotion(false)
        app.launchArguments = ["-AproposSmokeTesting", "-AproposIntroductionSmoke"]
        app.launch()
        let status = app.staticTexts.matching(identifier: "introduction.fixture.state").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let preconditions = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@",
            "systemReduceMotion=0", "systemReduceTransparency=0", "firebase=off")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: preconditions, object: status)], timeout: 5), .completed)
        app.terminate()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposIntroductionSmoke", "-IntroductionVisualOnly"]
        app.launch()
        XCTAssertTrue(app.staticTexts["introduction.welcome.title"].waitForExistence(timeout: 10))
        series("welcome-motion")
        try tap("introduction.welcome.signUp")
        try tap("introduction.account.google")
        XCTAssertTrue(app.staticTexts["introduction.fixture.account"].waitForExistence(timeout: 5))
        try tap("introduction.fixture.account.new")
        XCTAssertTrue(app.staticTexts["introduction.interests.title"].waitForExistence(timeout: 5))
        series("interests-motion")
        capture("interests-before-step")
        try tap("introduction.interests.skip")
        XCTAssertTrue(app.staticTexts["introduction.account.title"].waitForExistence(timeout: 5))
        capture("newsletter-after-step")
        series("newsletter-motion")

        try setReduceMotion(true)
        app.activate() // Preserve the current app process and backdrop identity.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        pause(0.5) // Allow the real system notification and scene update to settle.
        series("newsletter-system-reduced")
        capture("reduced-before-step")
        try tap("introduction.back")
        XCTAssertTrue(app.staticTexts["introduction.interests.title"].waitForExistence(timeout: 5))
        capture("reduced-after-step")
        pause(4)
        capture("reduced-after-step-plus4")

        try setReduceMotion(false)
        app.activate()
        pause(0.5)
        capture("resumed-0")
        pause(4)
        capture("resumed-4")
        let metadata = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: metadata, uniformTypeIdentifier: "public.json")
        attachment.name = "backdrop-capture-timestamps"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "Capture interval")], timeout: seconds)
    }
    private func series(_ name: String) {
        let start = ProcessInfo.processInfo.systemUptime
        for offset in [0, 4, 8] {
            pause(start + Double(offset) - ProcessInfo.processInfo.systemUptime)
            capture("\(name)-\(offset)")
        }
    }
    private func capture(_ name: String) {
        let before = ProcessInfo.processInfo.systemUptime
        let screenshot = app.screenshot()
        let after = ProcessInfo.processInfo.systemUptime
        records.append(["name": name, "captureStartedUptime": before, "captureEndedUptime": after])
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func tap(_ identifier: String) throws {
        let control = app.buttons[identifier]
        for _ in 0..<10 {
            if control.exists && control.isHittable { control.tap(); return }
            app.swipeUp()
        }
        attachHierarchy(app, name: "Missing capture control — " + identifier)
        throw CaptureFailure.control(identifier)
    }
    private func attachHierarchy(_ application: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: application.debugDescription)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func switchIsOn(_ control: XCUIElement) throws -> Bool {
        switch control.value as? String {
        case "1": return true
        case "0": return false
        default: attachHierarchy(settings, name: "Unknown system motion switch value"); throw CaptureFailure.unknownSwitchValue
        }
    }
    private func setReduceMotion(_ enabled: Bool) throws {
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
        attachHierarchy(settings, name: "Inspect actual Settings hierarchy before adjusting selectors")
        throw CaptureFailure.settingsHierarchy
    }
}
