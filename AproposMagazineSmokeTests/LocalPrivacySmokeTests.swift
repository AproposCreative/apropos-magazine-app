import XCTest
import CoreGraphics

/// Exercises the production privacy controls with injected local storage and sinks.
/// The fixture never configures Firebase or starts telemetry/background/network work.
final class LocalPrivacySmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRevealedRank = 0

    private enum Target: CaseIterable {
        case firebase, ready, failWrite, analytics, diagnostics, error, status, disableAll
        var rank: Int {
            switch self {
            case .firebase: return 1
            case .ready: return 2
            case .failWrite: return 3
            case .analytics: return 4
            case .diagnostics: return 5
            case .error, .status: return 6
            case .disableAll: return 7
            }
        }
        var id: String {
            switch self {
            case .firebase: return "privacy.firebase"
            case .ready: return "privacy.ready"
            case .failWrite: return "fixture.failWrite"
            case .analytics: return "privacy.analytics"
            case .diagnostics: return "privacy.crashReports"
            case .error: return "privacy.error"
            case .status: return "privacy.status"
            case .disableAll: return "privacy.disableAll"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRevealedRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposPrivacySmoke"]
        app.launch()
        let form = app.descendants(matching: .any).matching(identifier: "privacy.form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        reveal(.firebase)
        XCTAssertEqual(element(.firebase).label, "Firebase: ikke startet")
        reveal(.ready)
    }

    override func tearDownWithError() throws { app.terminate();app = nil }

    private func element(_ target: Target) -> XCUIElement {
        switch target {
        case .failWrite, .analytics, .diagnostics: return app.switches[target.id]
        case .disableAll: return app.buttons[target.id]
        case .firebase, .ready, .error, .status: return app.staticTexts[target.id]
        }
    }

    private var contentViewport: CGRect {
        let bounds = app.frame
        return CGRect(x: bounds.minX + 12, y: bounds.minY + 120,
                      width: max(1, bounds.width - 24), height: max(1, bounds.height - 164))
    }

    private func interactiveTarget(_ element: XCUIElement) -> XCUIElement {
        let knob = element.switches.firstMatch
        return knob.exists ? knob : element
    }

    /// Lazy rows may disappear entirely. A visible neighboring row is a better
    /// direction anchor than an old frame from before the previous scroll.
    private func visibleAnchorRank() -> Int? {
        let viewport = contentViewport
        var nearest: (distance: CGFloat, rank: Int)?
        for candidate in Target.allCases {
            let row = element(candidate)
            guard row.exists else { continue }
            let frame = interactiveTarget(row).frame
            guard !frame.isEmpty, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            let distance = abs(frame.midY - viewport.midY)
            if nearest == nil || distance < nearest!.distance { nearest = (distance, candidate.rank) }
        }
        return nearest?.rank
    }

    @discardableResult
    private func reveal(_ target: Target, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = element(target)
        for _ in 0..<24 {
            if row.exists {
                let control = interactiveTarget(row), frame = control.frame
                if !frame.isEmpty && frame.midX.isFinite && frame.midY.isFinite {
                    let center = CGPoint(x: frame.midX, y: frame.midY), viewport = contentViewport
                    if control.isHittable && viewport.contains(center) {
                        lastRevealedRank = target.rank
                        return control
                    }
                    if frame.midY < viewport.minY { app.swipeDown() }
                    else if frame.midY > viewport.maxY { app.swipeUp() }
                    else if frame.minY < viewport.minY { app.swipeDown() }
                    else { app.swipeUp() }
                    continue
                }
            }
            let anchor = visibleAnchorRank() ?? lastRevealedRank
            if target.rank < anchor { app.swipeDown() } else { app.swipeUp() }
        }
        let control = interactiveTarget(row)
        let frame = control.exists ? control.frame : .zero
        XCTFail("Privacy target \(target.id) is outside the visible content viewport: \(frame)", file: file, line: line)
        return control
    }

    private func tapSwitch(_ target: Target) { reveal(target).tap() }

    private func assertSwitch(_ target: Target, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        reveal(target, file: file, line: line)
        XCTAssertEqual(element(target).value as? String, enabled ? "1" : "0", file: file, line: line)
    }

    private func setSwitch(_ target: Target, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        reveal(target, file: file, line: line)
        if element(target).value as? String != (enabled ? "1" : "0") { tapSwitch(target) }
        assertSwitch(target, enabled: enabled, file: file, line: line)
    }

    private func assertSavedStatus(file: StaticString = #filePath, line: UInt = #line) {
        reveal(.status, file: file, line: line)
        XCTAssertEqual(element(.status).label, "Dine valg er gemt på denne enhed. Du kan ændre dem når som helst.", file: file, line: line)
        XCTAssertFalse(element(.error).exists, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testIndependentChoicesAndDisableAllUseSharedPrivacyControls() {
        assertSwitch(.analytics, enabled: false)
        assertSwitch(.diagnostics, enabled: false)
        capture("Privatliv — begge valg starter slået fra")
        setSwitch(.analytics, enabled: true)
        assertSwitch(.diagnostics, enabled: false)
        setSwitch(.diagnostics, enabled: true)
        capture("Privatliv — statistik og lokal log er særskilte valg")
        assertSwitch(.analytics, enabled: true)
        reveal(.disableAll).tap()
        capture("Privatliv — begge valg trukket tilbage")
        assertSwitch(.analytics, enabled: false)
        assertSwitch(.diagnostics, enabled: false)
        assertSavedStatus()
    }

    func testFailedSaveStaysDeniedAndCanBeRetried() {
        setSwitch(.failWrite, enabled: true)
        tapSwitch(.analytics)
        reveal(.error)
        XCTAssertTrue(element(.error).exists)
        capture("Privatliv — gemmefejl aktiverer ingen dataindsamling")
        assertSwitch(.analytics, enabled: false)
        assertSwitch(.diagnostics, enabled: false)
        setSwitch(.failWrite, enabled: false)
        setSwitch(.analytics, enabled: true)
        assertSwitch(.diagnostics, enabled: false)
        assertSavedStatus()
        capture("Privatliv — eksplicit retry efter lokal gemmefejl")
    }

    func testPrivacyCopyAndControlsRemainReachableAtCurrentTextSize() {
        reveal(.analytics)
        XCTAssertFalse(element(.analytics).label.isEmpty)
        XCTAssertGreaterThan(element(.analytics).frame.width, 100)
        capture("Privatliv — statistikforklaring ved valgt tema og tekststørrelse")
        reveal(.diagnostics)
        let diagnosticCopy = element(.diagnostics).label.lowercased()
        XCTAssertTrue(diagnosticCopy.contains("lokal") || diagnosticCopy.contains("denne enhed"), "The diagnostic choice must describe its local scope")
        XCTAssertGreaterThan(element(.diagnostics).frame.width, 100)
        capture("Privatliv — lokal log og lang forklaring")
        reveal(.disableAll)
        XCTAssertTrue(element(.disableAll).isHittable)
        capture("Privatliv — tilgængelig tilbagekaldelse ved valgt tekststørrelse")
    }
}
