import XCTest
import UIKit

final class ReaderResumeSmokeTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AproposSmokeTesting", "-AproposReaderResumeSmoke"]
        app.launch()
        waitReady(owner: "A", revision: 1)
        XCTAssertEqual(app.staticTexts["resume.fixture.firebase"].label, "Firebase: ikke startet")
    }
    override func tearDownWithError() throws { app?.terminate(); app = nil }
    private var status: XCUIElement { app.staticTexts["resume.fixture.status"] }
    private var percent: Int {
        let value = app.descendants(matching: .any).matching(identifier: "reader.progress").firstMatch.value as? String ?? ""
        return Int(value.components(separatedBy: " ").first ?? "") ?? -1
    }
    private func waitStatus(_ fragment: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", fragment), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func waitReady(owner: String, revision: Int) {
        let ready = app.staticTexts["resume.fixture.ready"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND label == %@", "Artikel klar · konto \(owner) · revision \(revision)"),
            object: ready)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
    private func readSome() {
        let scroll = app.scrollViews["resume.fixture.scroll"]
        for _ in 0..<3 { scroll.swipeUp() }
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (label CONTAINS %@)", "gemninger 0"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        XCTAssertGreaterThan(percent, 0)
        XCTAssertLessThan(percent, 100)
    }
    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func inspectVisibleParagraph() throws -> [String: Any] {
        let result = app.staticTexts["resume.fixture.visibleParagraph"]
        let previous = result.label
        app.buttons["resume.fixture.inspectParagraph"].tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            result.label != previous && result.label.hasPrefix("{")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 8), .completed)
        let attachment = XCTAttachment(string: result.label)
        attachment.name = "Synligt afsnit — læsende DOM-måling"
        attachment.lifetime = .keepAlways; add(attachment)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.label.utf8)) as? [String: Any])
    }
    private var savedWrites: Int {
        Int(status.label.components(separatedBy: "gemninger ").last ?? "") ?? -1
    }
    private var savedAnchorIndex: Int {
        let value = status.value as? String ?? ""
        return Int(value.components(separatedBy: ": ").last ?? "") ?? -1
    }
    private func waitForNewSave(after previous: Int) {
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.savedWrites > previous }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
    }
    private func waitInput(_ text: String) {
        let result = app.staticTexts["resume.fixture.inputResult"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }
    private func input(_ id: String, result: String) {
        let button = app.buttons["resume.fixture." + id]
        XCTAssertTrue(button.isHittable); button.tap(); waitInput(result)
    }
    private func recordSystemText() {
        let text = app.staticTexts["resume.fixture.textSize"]
        XCTAssertTrue(text.exists)
        XCTAssertTrue(["Systemtekst: standard", "Systemtekst: tilgængelighed"].contains(text.label))
        XCTContext.runActivity(named: "Programmatisk fælles inputfunktion — \(text.label)") { _ in }
    }
    private func revealResumeButton(_ button: XCUIElement) {
        // The fixture toolbar reduces the viewport. At maximum system text the
        // real notice must be fully visible, not merely tappable at one point.
        let scroll = app.scrollViews["resume.fixture.scroll"]
        let ready = app.staticTexts["resume.fixture.ready"]
        func visibleViewport() -> CGRect {
            var viewport = scroll.frame.intersection(app.frame)
            if ready.exists, ready.frame.intersects(viewport) {
                // The diagnostic Text has 4pt padding outside its AX frame.
                let bottom = min(viewport.maxY, ready.frame.minY - 6)
                viewport.size.height = max(0, bottom - viewport.minY)
            }
            return viewport
        }
        func fullyVisible() -> Bool {
            button.isHittable && !button.frame.isEmpty && visibleViewport().contains(button.frame)
        }
        for _ in 0..<8 where !fullyVisible() {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        }
        XCTAssertTrue(fullyVisible(), "Hele genoptagelsesknappen skal være synlig: \(button.frame), frit læseområde: \(visibleViewport())")
    }
    func testRealScrollStoresAnAnchorAndExplicitTapResumesAfterReopening() {
        XCTAssertFalse(app.buttons["reader.resume"].exists)
        readSome()
        let original = percent
        capture("Læsegenoptagelse — faktisk scroll og lokal gemning")
        app.buttons["resume.fixture.reopen"].tap()
        let button = app.buttons["reader.resume"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertEqual(percent, 0, "Genåbning skal blive ved begyndelsen indtil et eksplicit tryk")
        revealResumeButton(button)
        XCTAssertEqual(percent, 0, "Synliggørelse af knappen må ikke i sig selv genoptage læsningen")
        capture("Læsegenoptagelse — frivillig knap ved artikelteksten")
        button.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.percent > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 8), .completed)
        XCTAssertEqual(Double(percent), Double(original), accuracy: 12, "Genoptagelse skal lande ved det tidligere afsnit")
        XCTAssertFalse(app.staticTexts["reader.resume.message"].exists)
        capture("Læsegenoptagelse — tilbage ved gemt afsnit")
    }
    func testAnotherAccountAndChangedSourceCannotReuseTheOldOffer() {
        readSome()
        app.buttons["resume.fixture.b"].tap(); waitStatus("Konto B")
        waitReady(owner: "B", revision: 1)
        XCTAssertFalse(app.buttons["reader.resume"].exists)
        app.buttons["resume.fixture.a"].tap(); waitStatus("Konto A")
        XCTAssertTrue(app.buttons["reader.resume"].waitForExistence(timeout: 8))
        app.buttons["resume.fixture.revision"].tap(); waitStatus("revision 2")
        waitReady(owner: "A", revision: 2)
        XCTAssertFalse(app.buttons["reader.resume"].exists)
        XCTAssertEqual(percent, 0)
        capture("Læsegenoptagelse — ny artikeltekst genbruger ikke gammelt anker")
    }

    func testIPadRotationPreservesSavedParagraphAndExplicitResume() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Denne prøve kræver iPad")
        }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        readSome()
        let anchor = savedAnchorIndex
        XCTAssertGreaterThan(anchor, 0)
        let originalWrites = savedWrites
        let visibleBefore = try inspectVisibleParagraph()
        XCTAssertEqual(savedWrites, originalWrites, "Læsende måling må ikke skrive et anker")
        capture("iPad læser — gemt afsnit før rotation")
        func captureScreen(_ title: String) {
            // Give the existing reveal bridge time to paint after an instant
            // offset change. This is screenshot settling, not measured latency.
            Thread.sleep(forTimeInterval: 0.6)
            let screenshot = XCUIScreen.main.screenshot()
            XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height,
                "Hele skærmens billedopsamling skal følge den faktiske rotation")
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.width > self.app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
        XCTAssertEqual(savedAnchorIndex, anchor, "Rotation må ikke erstatte det gemte afsnit")
        XCTAssertTrue(app.scrollViews["resume.fixture.scroll"].isHittable)
        captureScreen("iPad læser — liggende efter rotation, hel skærm")
        let visibleAfter = try inspectVisibleParagraph()
        XCTAssertEqual(savedWrites, originalWrites, "Rotation/måling må ikke overskrive gemtanker")
        XCTAssertEqual(visibleAfter["index"] as? Int, visibleBefore["index"] as? Int,
            "Det synlige afsnit skal bevares ved rotation")
        XCTAssertEqual(visibleAfter["fingerprint"] as? String, visibleBefore["fingerprint"] as? String)
        app.buttons["resume.fixture.reopen"].tap()
        let button = app.buttons["reader.resume"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertEqual(percent, 0)
        revealResumeButton(button)
        button.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.percent > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 8), .completed)
        XCTAssertEqual(savedAnchorIndex, anchor)
        XCTAssertEqual(app.staticTexts["resume.fixture.firebase"].label, "Firebase: ikke startet")
        captureScreen("iPad læser — eksplicit genoptagelse i liggende format, hel skærm")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.frame.height > self.app.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        let visibleReturn = try inspectVisibleParagraph()
        XCTAssertEqual(visibleReturn["index"] as? Int, visibleBefore["index"] as? Int)
        XCTAssertEqual(visibleReturn["fingerprint"] as? String, visibleBefore["fingerprint"] as? String)
        XCTAssertEqual(savedWrites, originalWrites)
        XCTAssertEqual(savedAnchorIndex, anchor)
        capture("iPad læser — afsnit bevaret efter rotation tilbage")
    }

    /// The fixture buttons call the same captured action as accessibility/key
    /// input. This is programmatic native integration, not physical VO evidence.
    func testProgrammaticPageAndLineInputSavesAndExplicitlyResumesAfterReopening() {
        recordSystemText()
        for _ in 0..<3 { input("pageForward", result: "Side frem: udført") }
        // Pages cover fewer paragraphs at maximum text size. Read until the
        // actual persisted record has passed the first paragraph; a write
        // count alone also includes deliberate clearing of the heading anchor.
        for _ in 0..<16 where savedAnchorIndex < 2 {
            input("pageForward", result: "Side frem: udført")
        }
        waitForNewSave(after: 0)
        XCTAssertGreaterThanOrEqual(savedAnchorIndex, 2)
        XCTAssertGreaterThan(percent, 0); XCTAssertLessThan(percent, 100)
        input("lineForward", result: "Linje frem: udført")
        input("lineBackward", result: "Linje tilbage: udført")
        let beforeBackward = savedWrites
        input("pageBackward", result: "Side tilbage: udført")
        waitForNewSave(after: beforeBackward)
        XCTAssertGreaterThan(savedAnchorIndex, 0, "Tilbagehandlingen skal bevare et faktisk afsnitsanker")
        let original = percent
        XCTAssertGreaterThan(original, 0)
        capture("Programmatisk side og linje — faktisk artikel og gemt anker")
        app.buttons["resume.fixture.reopen"].tap()
        let button = app.buttons["reader.resume"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        XCTAssertEqual(percent, 0, "Genåbning må ikke selv flytte til den gemte position")
        revealResumeButton(button)
        XCTAssertEqual(percent, 0, "Synliggørelse af knappen må ikke i sig selv genoptage læsningen")
        capture("Programmatisk input — frivillig genoptagelse efter genåbning")
        button.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.percent > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 8), .completed)
        XCTAssertEqual(Double(percent), Double(original), accuracy: 12)
        XCTAssertFalse(app.staticTexts["reader.resume.message"].exists)
        capture("Programmatisk input — genoptaget ved det gemte afsnit")
    }

    func testCapturedProgrammaticInputCannotMoveNewReaderAfterAccountRoundTrip() {
        recordSystemText()
        input("captureInput", result: "Testhandling indfanget")
        let writes = savedWrites
        app.buttons["resume.fixture.b"].tap(); waitStatus("Konto B"); waitReady(owner: "B", revision: 1)
        input("applyCapturedInput", result: "Gammel handling: afvist")
        XCTAssertEqual(percent, 0); XCTAssertEqual(savedWrites, writes)
        app.buttons["resume.fixture.a"].tap(); waitStatus("Konto A"); waitReady(owner: "A", revision: 1)
        input("applyCapturedInput", result: "Gammel handling: afvist")
        XCTAssertEqual(percent, 0); XCTAssertEqual(savedWrites, writes)
        XCTAssertFalse(app.buttons["reader.resume"].exists)
        capture("Programmatisk input — gammel handling afvist efter A–B–A")
        for _ in 0..<3 { input("pageForward", result: "Side frem: udført") }
        waitForNewSave(after: writes)
        XCTAssertGreaterThan(percent, 0)
        XCTAssertEqual(app.staticTexts["resume.fixture.firebase"].label, "Firebase: ikke startet")
        capture("Programmatisk input — ny handling virker i den aktuelle artikel")
    }
}
