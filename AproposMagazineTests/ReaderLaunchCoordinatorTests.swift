import XCTest
@testable import Apropos

@MainActor
final class ReaderLaunchCoordinatorTests: XCTestCase {
    func testNewIntroductionPrecedesVersionNotesAndStartupIsIdempotent() {
        let model = ReaderLaunchCoordinator()
        model.start(needsIntroduction: true, needsWhatsNew: true, blocked: false)
        XCTAssertEqual(model.cover?.kind, .introduction)
        let original = model.cover?.id
        model.start(needsIntroduction: false, needsWhatsNew: true, blocked: false)
        XCTAssertEqual(model.cover?.id, original)
        model.finishIntroduction()
        XCTAssertNil(model.sheet)
        model.coverDidDismiss()
        XCTAssertTrue(model.isIdle)
    }

    func testAccountHandoffWaitsForTheCorrectActualDismissal() {
        let model = ReaderLaunchCoordinator()
        model.replay()
        model.finishIntroduction(then: .account(.init(topicIDs: ["music", "music", "culture"], provider: .google, newsletterOptIn: true)))
        XCTAssertNil(model.cover); XCTAssertNil(model.sheet)
        XCTAssertTrue(model.isAwaitingDismissal)
        model.sheetDidDismiss()
        XCTAssertNil(model.sheet)
        model.replay()
        XCTAssertNil(model.cover)
        model.coverDidDismiss()
        XCTAssertEqual(model.sheet?.kind, .account)
        XCTAssertEqual(model.sheet?.selectedTopicIDs, ["culture", "music"])
        XCTAssertEqual(model.sheet?.accountEntry.provider, .google)
        XCTAssertEqual(model.sheet?.accountEntry.newsletterOptIn, true)
        let original = model.sheet?.id
        model.coverDidDismiss()
        XCTAssertEqual(model.sheet?.id, original)
    }

    func testAccountChangeCancelsPendingInterestHandoffBeforeCoverDismisses() {
        let canonical = CanonicalSessionState()
        canonical.adopt(ReaderAccountSession(uid: "account-a", email: "a@example.invalid", isEmailVerified: true))
        let originalContext = canonical.contextTicket()
        let model = ReaderLaunchCoordinator()
        model.replay()
        model.finishIntroduction(then: .account(.init(topicIDs: ["private-a-topic"])), accountContext: originalContext)
        XCTAssertTrue(model.isAwaitingDismissal)
        XCTAssertNil(model.sheet)

        canonical.adopt(ReaderAccountSession(uid: "account-b", email: "b@example.invalid", isEmailVerified: true))
        model.reconcileAccountHandoff(with: canonical)
        XCTAssertTrue(model.isAwaitingDismissal, "The existing cover must finish dismissing before another modal may appear")
        model.coverDidDismiss()
        XCTAssertTrue(model.isIdle)
        XCTAssertNil(model.sheet, "Account B must never receive A's queued topic proposal")
        model.coverDidDismiss()
        XCTAssertTrue(model.isIdle)
    }

    func testAppearedAccountSheetRetainsOwnershipDuringGuestLogin() {
        let canonical = CanonicalSessionState()
        canonical.adopt(nil)
        let model = ReaderLaunchCoordinator()
        model.replay()
        model.finishIntroduction(then: .account(.init(topicIDs: ["music"])), accountContext: canonical.contextTicket())
        model.coverDidDismiss()
        XCTAssertEqual(model.sheet?.kind, .account)
        XCTAssertEqual(model.sheet?.selectedTopicIDs, ["music"])
        let sheetID = model.sheet?.id
        model.accountDidAppear()

        canonical.adopt(ReaderAccountSession(uid: "account-a", email: "a@example.invalid", isEmailVerified: true))
        model.reconcileAccountHandoff(with: canonical)
        XCTAssertEqual(model.sheet?.id, sheetID, "The visible account form owns login and explicit proposal adoption")
        XCTAssertFalse(model.isAwaitingDismissal)
        XCTAssertNil(model.cover)
    }

    func testIncomingLinkCancelsQueuedNewsletterWithoutCompletingAnotherFlow() {
        let model = ReaderLaunchCoordinator()
        model.replay()
        model.finishIntroduction(then: .newsletter)
        model.suspend()
        model.coverDidDismiss()
        XCTAssertTrue(model.isIdle)
        model.start(needsIntroduction: true, needsWhatsNew: true, blocked: false)
        XCTAssertTrue(model.isIdle)
    }

    func testAlreadyCompletedIntroductionShowsOnlyVersionNotes() {
        let model = ReaderLaunchCoordinator()
        model.start(needsIntroduction: false, needsWhatsNew: true, blocked: false)
        XCTAssertEqual(model.sheet?.kind, .whatsNew)
        model.dismissSheet()
        model.coverDidDismiss()
        XCTAssertTrue(model.isAwaitingDismissal)
        model.sheetDidDismiss()
        XCTAssertTrue(model.isIdle)
    }

    func testBusyLaunchDefersAutomaticPresentationButExplicitReplayRemainsPossible() {
        let model = ReaderLaunchCoordinator()
        model.start(needsIntroduction: true, needsWhatsNew: true, blocked: true)
        XCTAssertTrue(model.isIdle)
        model.start(needsIntroduction: true, needsWhatsNew: false, blocked: false)
        XCTAssertTrue(model.isIdle)
        model.replay()
        XCTAssertEqual(model.cover?.kind, .introduction)
    }

    func testSuspendingVisibleSheetWaitsForItsActualDismissal() {
        let model = ReaderLaunchCoordinator()
        model.replay(); model.finishIntroduction(then: .newsletter); model.coverDidDismiss()
        XCTAssertEqual(model.sheet?.kind, .newsletter)
        model.suspend()
        model.replay()
        XCTAssertNil(model.cover)
        model.sheetDidDismiss()
        model.replay()
        XCTAssertNotNil(model.cover)
    }
}
