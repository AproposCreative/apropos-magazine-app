import Foundation
import XCTest
@testable import Apropos

@MainActor
final class SupportContactModelTests: XCTestCase {
    private let body = "  Hej Apropos 🎵\nMin besked + spørgsmål & detaljer.  "

    func testConstructionAndEditingAreInertAndPreserveExactUserText() {
        let f = SupportFixture()
        XCTAssertEqual(f.model.state, .idle)
        f.model.updateMessage(body)
        XCTAssertEqual(f.model.message, body)
        XCTAssertNil(f.model.presentation)
        XCTAssertEqual(f.canComposeCalls, 0)
        XCTAssertTrue(f.openings.isEmpty)
        XCTAssertTrue(f.copies.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
    }

    func testEmptyOpenIsLocalAndNeverChecksMailOrStartsAnyPlatformEffect() {
        let f = SupportFixture()
        f.model.updateMessage(" \t\n")
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .emptyMessage)
        XCTAssertEqual(f.model.message, " \t\n")
        XCTAssertEqual(f.canComposeCalls, 0)
        XCTAssertTrue(f.openings.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
        XCTAssertTrue(f.copies.isEmpty)
    }

    func testComposerReceivesOnlyTheFixedDestinationSubjectAndFullDraft() throws {
        let f = SupportFixture()
        f.model.updateMessage(body)
        f.model.openMailDraft()
        let draft = try XCTUnwrap(f.model.presentation)
        XCTAssertEqual(f.model.state, .composing)
        XCTAssertEqual(draft.recipient, "support@aproposmagazine.com")
        XCTAssertEqual(draft.subject, SupportContactPolicy.subject)
        XCTAssertEqual(draft.body, body)
        XCTAssertEqual(f.model.message, body)
        XCTAssertTrue(f.openings.isEmpty)
        XCTAssertTrue(f.copies.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
    }

    func testRepeatedOpenTapsCoalesceWhileAComposerIsPresented() throws {
        let f = SupportFixture()
        f.model.updateMessage(body)
        f.model.openMailDraft()
        let draft = try XCTUnwrap(f.model.presentation)
        for _ in 0..<20 { f.model.openMailDraft() }
        XCTAssertEqual(f.canComposeCalls, 1)
        XCTAssertEqual(f.model.presentation, draft)
    }

    func testEveryComposerOutcomeIsHonestAndPreservesTheDraftDespiteDuplicateDismissCallbacks() throws {
        let cases: [(SupportContactModel.ComposerResult, SupportContactModel.State)] = [
            (.sent, .handedToMail), (.saved, .draftSaved), (.cancelled, .cancelled), (.failed, .composerFailed)
        ]
        for (result, expected) in cases {
            let f = SupportFixture()
            f.model.updateMessage(body)
            f.model.openMailDraft()
            let id = try XCTUnwrap(f.model.presentation).id
            f.model.finishComposer(id: id, result: result)
            XCTAssertEqual(f.model.state, expected)
            XCTAssertNil(f.model.presentation)
            XCTAssertEqual(f.model.message, body)
            f.model.composerDismissed(id: id)
            f.model.finishComposer(id: id, result: .failed)
            XCTAssertEqual(f.model.state, expected)
            XCTAssertEqual(f.model.message, body)
        }
    }

    func testInteractiveComposerDismissalRetainsTextAndIgnoresUnknownDraftIDs() throws {
        let f = SupportFixture()
        f.model.updateMessage(body)
        f.model.openMailDraft()
        let id = try XCTUnwrap(f.model.presentation).id
        f.model.composerDismissed(id: UUID())
        XCTAssertEqual(f.model.presentation?.id, id)
        f.model.composerDismissed(id: id)
        XCTAssertEqual(f.model.state, .cancelled)
        XCTAssertEqual(f.model.message, body)
    }

    func testEditingInvalidatesOldComposerResultsBeforeTheNextDraftIsPresented() throws {
        let f = SupportFixture()
        f.model.updateMessage(body)
        f.model.openMailDraft()
        let old = try XCTUnwrap(f.model.presentation)
        f.model.updateMessage("En ny besked")
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertNil(f.model.presentation)
        f.model.openMailDraft()
        let current = try XCTUnwrap(f.model.presentation)
        XCTAssertNotEqual(current.id, old.id)
        f.model.finishComposer(id: old.id, result: .sent)
        f.model.composerDismissed(id: old.id)
        XCTAssertEqual(f.model.state, .composing)
        XCTAssertEqual(f.model.presentation, current)
        XCTAssertEqual(current.body, "En ny besked")
    }

    func testContextInvalidationClosesOldComposerEvidenceButDoesNotEraseReaderText() throws {
        let f = SupportFixture()
        f.model.updateMessage(body)
        f.model.openMailDraft()
        let id = try XCTUnwrap(f.model.presentation).id
        f.model.invalidateContext()
        f.model.finishComposer(id: id, result: .sent)
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertNil(f.model.presentation)
        XCTAssertEqual(f.model.message, body)
    }

    func testExternalMailAcceptedMeansOpenedAndNeverClearsOrClaimsSent() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .openingMailApp)
        XCTAssertEqual(f.openings.count, 1)
        XCTAssertEqual(f.wakes.count, 1)
        XCTAssertEqual(f.wakes[0].delay, 8)
        XCTAssertEqual(URLComponents(url: f.openings[0].url, resolvingAgainstBaseURL: false)?.queryItems?.last?.value, body)
        f.openings[0].completion(true)
        XCTAssertEqual(f.model.state, .mailAppOpened)
        XCTAssertEqual(f.model.message, body)
        XCTAssertTrue(f.wakes[0].cancelled)
        f.openings[0].completion(false)
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .mailAppOpened)
    }

    func testDeclinedExternalMailFallsBackWithoutDroppingTheDraftOrCopyingAutomatically() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.openings[0].completion(false)
        XCTAssertEqual(f.model.state, .manualFallback)
        XCTAssertEqual(f.model.message, body)
        XCTAssertTrue(f.copies.isEmpty)
    }

    func testMissingOpenCallbackTimesOutAndRetryFencesBothLateAcknowledgementAndOldTimer() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .openingTimedOut)
        XCTAssertEqual(f.model.message, body)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .openingMailApp)
        XCTAssertEqual(f.openings.count, 2)
        f.openings[0].completion(true)
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .openingMailApp)
        f.openings[1].completion(false)
        XCTAssertEqual(f.model.state, .manualFallback)
    }

    func testRepeatedOpenTapsDoNotCreateDuplicateExternalLaunchesOrDeadlines() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        for _ in 0..<20 { f.model.openMailDraft() }
        XCTAssertEqual(f.canComposeCalls, 1)
        XCTAssertEqual(f.openings.count, 1)
        XCTAssertEqual(f.wakes.count, 1)
    }

    func testEditingFencesLateExternalOpenAndTimeoutCallbacks() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.model.updateMessage("Ny og privat tekst")
        XCTAssertTrue(f.wakes[0].cancelled)
        f.openings[0].completion(true)
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, "Ny og privat tekst")
    }

    func testContextInvalidationFencesLateExternalOpenWithoutStartingAnotherHandoff() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.model.invalidateContext()
        f.openings[0].completion(true)
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, body)
        XCTAssertEqual(f.openings.count, 1)
    }

    func testOversizedMailURLKeepsFullTextForAnExplicitManualCopy() {
        let f = SupportFixture(canCompose: false), large = String(repeating: "🎵 + & ", count: 500)
        f.model.updateMessage(large)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .manualFallback)
        XCTAssertTrue(f.openings.isEmpty)
        XCTAssertTrue(f.wakes.isEmpty)
        XCTAssertTrue(f.copies.isEmpty)
        f.model.copyMessage()
        XCTAssertEqual(f.copies, [large])
        XCTAssertEqual(f.model.state, .messageCopied)
        XCTAssertEqual(f.model.message, large)
    }

    func testHugeBodyNeverCreatesAnUnboundedPlatformComposerAndCanStillBeCopiedInFull() {
        let f = SupportFixture(), huge = String(repeating: "x", count: SupportContactPolicy.maximumComposerBodyBytes + 1)
        f.model.updateMessage(huge)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .manualFallback)
        XCTAssertNil(f.model.presentation)
        XCTAssertEqual(f.canComposeCalls, 0)
        XCTAssertTrue(f.openings.isEmpty)
        f.model.copyMessage()
        XCTAssertEqual(f.copies, [huge])
        XCTAssertEqual(f.model.message, huge)
    }

    func testAddressCopyIsExplicitAndDoesNotRequireOrAlterAMessage() {
        let f = SupportFixture()
        XCTAssertTrue(f.copies.isEmpty)
        f.model.copyAddress()
        XCTAssertEqual(f.copies, [SupportContactPolicy.recipient])
        XCTAssertEqual(f.model.state, .addressCopied)
        XCTAssertEqual(f.model.message, "")
        XCTAssertTrue(f.openings.isEmpty)
    }

    func testCopyFailureNeverClaimsTheMessageWasCopiedAndRetainsItForRetry() {
        let f = SupportFixture()
        f.copyAllowed = false
        f.model.updateMessage(body)
        f.model.copyMessage()
        XCTAssertEqual(f.model.state, .copyFailed)
        XCTAssertEqual(f.model.message, body)
        f.copyAllowed = true
        f.model.copyMessage()
        XCTAssertEqual(f.model.state, .messageCopied)
        XCTAssertEqual(f.copies, [body, body])
    }

    func testEmptyMessageCopyDoesNotTouchTheClipboard() {
        let f = SupportFixture()
        f.model.updateMessage(" \n")
        f.model.copyMessage()
        XCTAssertEqual(f.model.state, .emptyMessage)
        XCTAssertTrue(f.copies.isEmpty)
    }

    func testCopyFeedbackCannotBeReplacedByAnOlderExternalOpenCallback() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.model.copyMessage()
        f.openings[0].completion(true)
        f.wakes[0].fireIgnoringCancellation()
        XCTAssertEqual(f.model.state, .messageCopied)
        XCTAssertEqual(f.copies, [body])
    }

    func testSynchronousDeadlinePreventsALateExternalLaunchAndCancelsItsReturnedHandle() {
        let f = SupportFixture(canCompose: false)
        f.fireImmediately = true
        f.model.updateMessage(body)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .openingTimedOut)
        XCTAssertTrue(f.openings.isEmpty)
        XCTAssertEqual(f.wakes.count, 1)
        XCTAssertTrue(f.wakes[0].cancelled)
    }

    func testReentrantAvailabilityCheckCannotPresentAnObsoleteDraft() {
        let f = SupportFixture()
        f.availabilityHook = { f.model.updateMessage("Ny tekst fra en nyere handling") }
        f.model.updateMessage(body)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, "Ny tekst fra en nyere handling")
        XCTAssertNil(f.model.presentation)
        XCTAssertTrue(f.openings.isEmpty)
    }

    func testReentrantExternalOpenerCannotAcknowledgeAnEditedDraft() {
        let f = SupportFixture(canCompose: false)
        f.openHook = { completion in
            f.model.updateMessage("Ny tekst")
            completion(true)
        }
        f.model.updateMessage(body)
        f.model.openMailDraft()
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, "Ny tekst")
        XCTAssertTrue(f.wakes[0].cancelled)
    }

    func testCancellationReentryCannotOverwriteANewerDraftWithAnOldOpenResult() {
        let f = SupportFixture(canCompose: false)
        f.model.updateMessage(body)
        f.model.openMailDraft()
        f.cancelHook = { f.model.updateMessage("Nyere handling under cancellation") }
        f.openings[0].completion(true)
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, "Nyere handling under cancellation")
    }

    func testReentrantCopyResultCannotOverwriteANewerDraftStatus() {
        let f = SupportFixture()
        f.copyHook = { f.model.updateMessage("Ny tekst mens kopi afsluttes") }
        f.model.updateMessage(body)
        f.model.copyMessage()
        XCTAssertEqual(f.model.state, .idle)
        XCTAssertEqual(f.model.message, "Ny tekst mens kopi afsluttes")
        XCTAssertEqual(f.copies, [body])
    }
}

@MainActor
private final class SupportFixture {
    struct Opening {
        let url: URL
        let completion: SupportContactModel.Completion
    }
    @MainActor
    final class Wake {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) { self.delay = delay;self.action = action }
        func fireIgnoringCancellation() { action() }
    }
    var available: Bool
    var copyAllowed = true
    var fireImmediately = false
    var canComposeCalls = 0
    var openings: [Opening] = []
    var copies: [String] = []
    var wakes: [Wake] = []
    var availabilityHook: (() -> Void)?
    var openHook: ((SupportContactModel.Completion) -> Void)?
    var copyHook: (() -> Void)?
    var cancelHook: (() -> Void)?
    init(canCompose: Bool = true) { available = canCompose }
    lazy var model = SupportContactModel(
        canCompose: { [unowned self] in canComposeCalls += 1;availabilityHook?();return available },
        openURL: { [unowned self] url, completion in openings.append(.init(url: url, completion: completion));openHook?(completion) },
        copy: { [unowned self] text in copies.append(text);copyHook?();return copyAllowed },
        schedule: { [unowned self] delay, action in
            let wake = Wake(delay: delay, action: action)
            wakes.append(wake)
            if fireImmediately { wake.fireIgnoringCancellation() }
            return { [weak self] in wake.cancelled = true;self?.cancelHook?() }
        })
}
