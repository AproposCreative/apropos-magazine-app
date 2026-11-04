import XCTest
import CoreGraphics

/// Uses the production support sections with in-memory transport/copy effects.
/// No scenario presents native Mail, initializes Firebase or reads the clipboard.
final class SupportContactSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var lastRevealedRank = 0

    private enum Target: Int, CaseIterable {
        case firebase, ready, openFails, canCompose, openCount, copyCount, copyResult
        case address, message, openDraft, status, copyAddress, copyMessage, cancelComposer, sentComposer

        var id: String {
            switch self {
            case .firebase: return "support.fixture.firebase"
            case .ready: return "support.fixture.ready"
            case .openFails: return "fixture.support.openFails"
            case .canCompose: return "fixture.support.canCompose"
            case .openCount: return "support.fixture.openCount"
            case .copyCount: return "support.fixture.copyCount"
            case .copyResult: return "support.fixture.copyResult"
            case .address: return "support.address"
            case .message: return "support.message"
            case .openDraft: return "support.openDraft"
            case .status: return "support.status"
            case .copyAddress: return "support.copyAddress"
            case .copyMessage: return "support.copyMessage"
            case .cancelComposer: return "support.fixture.cancelComposer"
            case .sentComposer: return "support.fixture.sentComposer"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        lastRevealedRank = 0
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposSupportSmoke"]
        app.launch()
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
        XCTAssertEqual(reveal(.ready).label, "Lokal supporttest klar")
    }

    override func tearDownWithError() throws { app.terminate();app = nil }

    private var form: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "support.fixture.form").firstMatch
    }

    private func element(_ target: Target) -> XCUIElement {
        switch target {
        case .openFails, .canCompose: return app.switches[target.id]
        case .message: return app.textViews[target.id]
        case .openDraft, .copyAddress, .copyMessage, .cancelComposer, .sentComposer: return app.buttons[target.id]
        case .firebase, .ready, .openCount, .copyCount, .copyResult, .address, .status: return app.staticTexts[target.id]
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

    private func visibleAnchorRank() -> Int? {
        let viewport = contentViewport
        var nearest: (distance: CGFloat, rank: Int)?
        for candidate in Target.allCases {
            let row = element(candidate)
            guard row.exists else { continue }
            let frame = interactiveTarget(row).frame
            guard !frame.isEmpty, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            let distance = abs(frame.midY - viewport.midY)
            if nearest == nil || distance < nearest!.distance { nearest = (distance, candidate.rawValue) }
        }
        return nearest?.rank
    }

    /// Form rows are lazy. Scroll toward an actual visible neighbor and only tap
    /// controls whose centers are inside the content viewport, clear of toolbars.
    @discardableResult
    private func reveal(_ target: Target, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = element(target)
        for _ in 0..<28 {
            if row.exists {
                let control = interactiveTarget(row), frame = control.frame
                if !frame.isEmpty && frame.midX.isFinite && frame.midY.isFinite {
                    let viewport = contentViewport
                    if control.isHittable && viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                        lastRevealedRank = target.rawValue
                        return control
                    }
                    if frame.midY < viewport.minY || frame.minY < viewport.minY { form.swipeDown() }
                    else { form.swipeUp() }
                    continue
                }
            }
            let anchor = visibleAnchorRank() ?? lastRevealedRank
            if target.rawValue < anchor { form.swipeDown() } else { form.swipeUp() }
        }
        let control = interactiveTarget(row)
        XCTFail("Support target \(target.id) is outside the content viewport: \(control.exists ? control.frame : .zero)", file: file, line: line)
        return control
    }

    private func setSwitch(_ target: Target, enabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let control = reveal(target, file: file, line: line)
        if element(target).value as? String != (enabled ? "1" : "0") { control.tap() }
        XCTAssertEqual(element(target).value as? String, enabled ? "1" : "0", file: file, line: line)
    }

    private func enter(_ body: String) {
        let editor = reveal(.message)
        editor.tap()
        editor.typeText(body)
        // The fixture Form dismisses on drag, without a UIKit/keyboard hook.
        form.swipeUp()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    private func assertMessage(_ body: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reveal(.message, file: file, line: line).value as? String, body, file: file, line: line)
    }

    private func assertStatus(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(.status, file: file, line: line)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element(.status))
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWhitespaceCannotOpenTransportAndSharedControlsAreReachable() {
        let body = "   \n   "
        enter(body)
        reveal(.openDraft).tap()
        assertStatus("Skriv en besked, før du åbner mailkladden.")
        capture("Support — tom besked åbner ingen mailkladde")
        assertMessage(body)
        XCTAssertEqual(reveal(.openCount).label, "Mail-app-åbninger: 0")
        XCTAssertEqual(reveal(.copyCount).label, "Kopieringer i hukommelsen: 0")
        XCTAssertEqual(reveal(.address).label, "support@aproposmagazine.com")
        XCTAssertFalse(reveal(.copyMessage).isEnabled)
        XCTAssertTrue(reveal(.copyAddress).isHittable)
        XCTAssertFalse(element(.cancelComposer).exists)
        capture("Support — kontaktadresse og kopiknapper ved valgt tekststørrelse")
    }

    func testFailedMailAppHandoffPreservesTextAndAcceptedRetryDoesNotClaimDelivery() {
        let body = "Hej Apropos. Jeg har brug for hjælp til en artikel.\nMin fulde besked skal bevares."
        enter(body)
        reveal(.openDraft).tap()
        assertStatus("Mailkladden kunne ikke åbnes. Kopiér adressen og din besked til din mailapp. Din fulde tekst er bevaret her.")
        capture("Support — fejl ved åbning bevarer beskeden")
        assertMessage(body)
        setSwitch(.openFails, enabled: false)
        reveal(.openDraft).tap()
        assertStatus("Fortsæt i din mailapp, og tjek modtager og besked. Afsendelse er ikke bekræftet. Din tekst er bevaret her.")
        capture("Support — accepteret åbning er ikke bekræftet afsendelse")
        XCTAssertEqual(reveal(.openCount).label, "Mail-app-åbninger: 2")
        reveal(.copyAddress).tap()
        assertStatus("E-mailadressen er kopieret.")
        reveal(.copyMessage).tap()
        assertStatus("Beskeden er kopieret. Teksten står også stadig her.")
        assertMessage(body)
        XCTAssertEqual(reveal(.copyCount).label, "Kopieringer i hukommelsen: 2")
        XCTAssertEqual(reveal(.copyResult).label, "Kopieret tekst matcher hele beskeden")
    }

    func testComposerCancellationAndSendKeepFullTextWithTruthfulQueuedStatus() {
        let body = "Hej redaktion. Her er en besked med flere linjer.\nTak for magasinet."
        setSwitch(.canCompose, enabled: true)
        enter(body)
        reveal(.openDraft).tap()
        assertStatus("Mailkladden er åben. Du vælger selv, om den skal sendes, gemmes eller afbrydes.")
        reveal(.cancelComposer).tap()
        assertStatus("Du afbrød mailkladden. Din tekst er bevaret her.")
        assertMessage(body)
        capture("Support — afbrudt mailkladde bevarer hele teksten")
        reveal(.openDraft).tap()
        reveal(.sentComposer).tap()
        assertStatus("Mail har lagt beskeden i kø til afsendelse. Modtagelse er ikke bekræftet. Din tekst er bevaret her.")
        capture("Support — Mail-resultat beskriver kø frem for modtagelse")
        assertMessage(body)
        XCTAssertEqual(reveal(.openCount).label, "Mail-app-åbninger: 0")
        XCTAssertEqual(reveal(.copyCount).label, "Kopieringer i hukommelsen: 0")
        XCTAssertEqual(reveal(.firebase).label, "Firebase: ikke startet")
    }
}
