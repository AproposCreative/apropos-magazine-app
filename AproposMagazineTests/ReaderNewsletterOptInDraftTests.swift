import Combine
import UIKit
import XCTest
@testable import Apropos

@MainActor
final class ReaderNewsletterOptInDraftTests: XCTestCase {
    private func account(_ uid: String, verified: Bool = true) -> ReaderAccountSession {
        ReaderAccountSession(uid: uid, email: uid + "@example.invalid", isEmailVerified: verified)
    }

    func testDefaultAccountSheetDoesNotInventConsent() {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(account("A"))
        let draft = ReaderNewsletterOptInDraft(canonical: canonical)
        XCTAssertFalse(draft.selected)
        XCTAssertFalse(draft.isSelected(for: canonical.contextTicket()))
    }

    func testExplicitSignedInEntryRetainsCheckedChoiceForExactlyOneHandoff() throws {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(account("A"))
        let original = canonical.contextTicket()
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        XCTAssertTrue(draft.isSelected(for: original))
        XCTAssertEqual(try XCTUnwrap(draft.consumeInitialEntryContext()), original)
        XCTAssertNil(draft.consumeInitialEntryContext())
        XCTAssertTrue(draft.initialEntryIsCurrent, "The same queued provider still needs to validate its owner after consumption")
    }

    func testUnresolvedEntryCannotRestoreConsentWhenGuestResolvesButManualChoiceWorks() {
        let canonical = CanonicalSessionState()
        let unresolved = canonical.contextTicket()
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        XCTAssertFalse(draft.selected)
        XCTAssertFalse(draft.setSelected(true, context: unresolved))
        _ = canonical.adopt(nil)
        let guest = canonical.contextTicket()
        XCTAssertFalse(draft.selected)
        XCTAssertNil(draft.consumeInitialEntryContext())
        XCTAssertTrue(draft.setSelected(true, context: guest))
        XCTAssertTrue(draft.isSelected(for: guest))
        XCTAssertFalse(draft.initialEntryIsCurrent, "A fresh manual checkbox does not restore the original automatic provider entry")
    }

    func testAccountSwitchAndReturnBeforeAnyRenderPermanentlyClearOriginalConsent() {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(account("A"))
        let original = canonical.contextTicket()
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        _ = canonical.adopt(account("B"))
        _ = canonical.adopt(account("A"))
        XCTAssertFalse(draft.selected)
        XCTAssertFalse(draft.isSelected(for: original))
        XCTAssertFalse(draft.setSelected(true, context: original))
        XCTAssertNil(draft.consumeInitialEntryContext())
        XCTAssertTrue(draft.setSelected(true, context: canonical.contextTicket()))
        XCTAssertTrue(draft.selected)
        XCTAssertFalse(draft.initialEntryIsCurrent)
    }

    func testGuestGenerationReplacementRejectsStaleRenderedCheckboxAndQueuedActivation() throws {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(nil)
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        let scheduledContext = try XCTUnwrap(draft.consumeInitialEntryContext())
        _ = canonical.adopt(nil, forceNewGeneration: true)
        XCTAssertFalse(canonical.isCurrent(scheduledContext))
        XCTAssertFalse(draft.initialEntryIsCurrent)
        XCTAssertFalse(draft.selected)
        XCTAssertFalse(draft.setSelected(true, context: scheduledContext))
        XCTAssertNil(draft.consumeInitialEntryContext())
    }

    func testGenerationChangeBeforeFirstUIKitAppearanceCannotRelabelInitialEntry() {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(nil)
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        _ = canonical.adopt(account("A"))
        _ = canonical.adopt(nil)
        XCTAssertNil(draft.consumeInitialEntryContext())
        XCTAssertFalse(draft.initialEntryIsCurrent)
        XCTAssertFalse(draft.selected)
    }

    func testReadIsRevokedBeforeDraftsOwnCanonicalSubscriberRuns() {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(account("A"))
        var draft: ReaderNewsletterOptInDraft?
        var observed: [Bool] = []
        let observer = canonical.changes.sink { _ in observed.append(draft?.selected ?? false) }
        draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        _ = canonical.adopt(account("B"))
        XCTAssertEqual(observed, [false])
        XCTAssertEqual(draft?.selected, false)
        withExtendedLifetime(observer) {}
    }

    func testReentrantAccountChangeDuringCheckboxNotificationCannotRestoreChoice() {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(nil)
        let original = canonical.contextTicket()
        let draft = ReaderNewsletterOptInDraft(canonical: canonical)
        var notifications = 0
        let observer = draft.objectWillChange.sink {
            notifications += 1
            _ = canonical.adopt(nil, forceNewGeneration: true)
        }
        XCTAssertFalse(draft.setSelected(true, context: original))
        XCTAssertEqual(notifications, 1)
        XCTAssertFalse(draft.selected)
        XCTAssertNil(draft.consumeInitialEntryContext())
        withExtendedLifetime(observer) {}
    }

    func testSameOwnerVerificationPreservesChoiceAndOriginalHandoff() throws {
        let canonical = CanonicalSessionState()
        _ = canonical.adopt(account("A", verified: false))
        let original = canonical.contextTicket()
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        _ = canonical.adopt(account("A", verified: true))
        XCTAssertTrue(draft.isSelected(for: original))
        XCTAssertEqual(try XCTUnwrap(draft.consumeInitialEntryContext()), original)
    }

    func testAnotherCanonicalModelCannotReadOrSetConsentWithMatchingUser() {
        let canonical = CanonicalSessionState(), unrelated = CanonicalSessionState()
        _ = canonical.adopt(account("A"))
        _ = unrelated.adopt(account("A"))
        let draft = ReaderNewsletterOptInDraft(canonical: canonical, selected: true)
        XCTAssertFalse(draft.isSelected(for: unrelated.contextTicket()))
        XCTAssertFalse(draft.setSelected(false, context: unrelated.contextTicket()))
        XCTAssertTrue(draft.selected)
    }

    func testUIKitActivationWaitsForWindowAndFiresOnlyOnceAcrossAppearances() {
        var activations = 0
        let controller = AccountEntryActivation.Controller { activations += 1 }
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        XCTAssertEqual(activations, 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.addSubview(controller.view)
        controller.viewDidAppear(false)
        controller.onReady = { activations += 10 }
        controller.viewDidAppear(false)
        XCTAssertEqual(activations, 1)
        controller.view.removeFromSuperview()
    }

    func testInvalidatedUIKitActivationCannotStartTheOriginalOrReplacementCallback() {
        var activations = 0
        let controller = AccountEntryActivation.Controller { activations += 1 }
        controller.loadViewIfNeeded()
        controller.invalidate()
        controller.onReady = { activations += 10 }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.addSubview(controller.view)
        controller.viewDidAppear(false)
        XCTAssertEqual(activations, 0)
        controller.view.removeFromSuperview()
    }
}
