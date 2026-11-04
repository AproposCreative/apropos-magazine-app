import Combine
import XCTest
@testable import Apropos

@MainActor
final class CanonicalSessionStateTests: XCTestCase {
    private func session(_ uid: String = "A", verified: Bool = false, email: String? = nil) -> ReaderAccountSession {
        ReaderAccountSession(uid: uid, email: email ?? uid + "@example.invalid", isEmailVerified: verified)
    }
    func testConstructionIsUnresolvedAndStartsNoVerificationOrRefresh() {
        let state = CanonicalSessionState()
        XCTAssertEqual(state.snapshot.context, .unresolved); XCTAssertNil(state.snapshot.session)
        XCTAssertNil(state.snapshot.verificationMessage); XCTAssertEqual(state.snapshot.verificationStatus, .idle)
        XCTAssertNil(state.beginVerification(context: state.contextTicket()))
        XCTAssertNil(state.beginRefresh(context: state.contextTicket()))
    }
    func testConfirmedGuestIsDistinctFromUnresolvedAndHasNoAccountAuthority() {
        let state = CanonicalSessionState(); let initial = state.contextTicket()
        let guest = state.adopt(nil)
        XCTAssertEqual(state.snapshot.context, .guest); XCTAssertNil(state.snapshot.session)
        XCTAssertNotNil(guest); XCTAssertFalse(state.isCurrent(initial))
        XCTAssertNil(state.beginVerification(context: state.contextTicket()))
        XCTAssertNil(state.beginRefresh(context: state.contextTicket()))
    }
    func testInvalidUIDCannotPublishAnAccountOrChangeCommittedState() {
        let state = CanonicalSessionState(); let initial = state.snapshot
        for invalid in ["", " A", "A\n", ".", "..", "a/b", "__reserved__", String(repeating: "a", count: 513)] {
            XCTAssertNil(state.adopt(session(invalid))); XCTAssertEqual(state.snapshot, initial)
        }
    }
    func testAcceptedOriginalProviderValueIsReturnedWithoutReadingLaterSession() throws {
        let state = CanonicalSessionState(); let original = session()
        let context = try XCTUnwrap(state.adopt(original))
        XCTAssertEqual(state.acceptedSession(original, ticket: context), original)
        _ = state.adopt(session("B"))
        XCTAssertNil(state.acceptedSession(original, ticket: context))
        XCTAssertNil(state.acceptedSession(session("B"), ticket: context))
    }
    func testSameOwnerUpdatedProviderValueDoesNotReturnNewMutableSessionForOldResult() throws {
        let state = CanonicalSessionState(); let original = session()
        let context = try XCTUnwrap(state.adopt(original)); let generation = state.snapshot.generation
        let updated = session(verified: true)
        _ = state.adopt(updated)
        XCTAssertEqual(state.snapshot.generation, generation); XCTAssertTrue(state.isCurrent(context))
        XCTAssertNil(state.acceptedSession(original, ticket: context))
        XCTAssertEqual(state.acceptedSession(updated, ticket: context), updated)
    }
    func testAccountGuestSameAccountNeverRevivesOriginalTickets() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let verification = try XCTUnwrap(state.beginVerification(context: context))
        _ = state.adopt(nil); _ = state.adopt(session())
        XCTAssertFalse(state.isCurrent(context)); XCTAssertFalse(state.isCurrent(verification))
        XCTAssertFalse(state.finishVerification(ticket: verification, message: "Old"))
        XCTAssertNil(state.acceptedSession(session(), ticket: context))
    }
    func testSuspensionRevokesBeforeSignoutAndFailedSignoutGetsFreshEpoch() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let refresh = try XCTUnwrap(state.beginRefresh(context: context))
        _ = state.suspend()
        XCTAssertEqual(state.snapshot.context, .unresolved); XCTAssertNil(state.snapshot.session)
        XCTAssertFalse(state.isCurrent(context)); XCTAssertFalse(state.isCurrent(refresh))
        let restored = try XCTUnwrap(state.adopt(session()))
        XCTAssertNotEqual(restored.generation, context.generation)
        XCTAssertFalse(state.acceptRefresh(session(verified: true), ticket: refresh))
    }
    func testWillChangeReentryCannotCommitOuterAccountOverNewerAccount() {
        let state = CanonicalSessionState(); _ = state.adopt(session())
        var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.adopt(self.session("C")) }
        }
        XCTAssertNil(state.adopt(session("B")))
        XCTAssertEqual(state.snapshot.session?.uid, "C")
        withExtendedLifetime(subscription) {}
    }
    func testNestedSameCommittedOwnerCancelsOuterAccountProposalBeforeAssignment() {
        let state = CanonicalSessionState(); _ = state.adopt(session()); let original = state.snapshot
        var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.adopt(self.session()) }
        }
        XCTAssertNil(state.adopt(session("B"))); XCTAssertEqual(state.snapshot, original)
        withExtendedLifetime(subscription) {}
    }
    func testEachSubscriberRejectsOuterOwnerAfterNestedNewOwnerDelivery() {
        let state = CanonicalSessionState(); var replaced = false
        var received: [[CanonicalSessionState.Snapshot]] = [[], []]
        func consume(_ candidate: CanonicalSessionState.Snapshot, index: Int) {
            XCTAssertEqual(candidate, state.snapshot)
            received[index].append(candidate)
            if !replaced, candidate.userID == "A" { replaced = true; _ = state.adopt(self.session("B")) }
        }
        let first = state.changes.sink { consume($0, index: 0) }
        let next = state.changes.sink { consume($0, index: 1) }
        XCTAssertNil(state.adopt(session()))
        for values in received {
            let replacement = values.firstIndex(where: { $0.userID == "B" })
            XCTAssertNotNil(replacement)
            if let replacement { XCTAssertFalse(values[replacement...].contains(where: { $0.userID == "A" })) }
        }
        withExtendedLifetime((first, next)) {}
    }
    func testEachSubscriberRejectsOldSameGenerationVerificationMessageAfterNestedChange() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let ticket = try XCTUnwrap(state.beginVerification(context: context)); var replaced = false
        var received: [[CanonicalSessionState.Snapshot]] = [[], []]
        func consume(_ candidate: CanonicalSessionState.Snapshot, index: Int) {
            XCTAssertEqual(candidate, state.snapshot); received[index].append(candidate)
            if !replaced, candidate.verificationMessage == "outer" {
                replaced = true
                if let inner = state.beginVerification(context: context) { _ = state.finishVerification(ticket: inner, message: "inner") }
            }
        }
        let first = state.changes.sink { consume($0, index: 0) }
        let next = state.changes.sink { consume($0, index: 1) }
        XCTAssertFalse(state.finishVerification(ticket: ticket, message: "outer"))
        XCTAssertEqual(state.snapshot.verificationMessage, "inner")
        for values in received {
            let replacement = values.firstIndex(where: { $0.verificationMessage == "inner" })
            XCTAssertNotNil(replacement)
            if let replacement { XCTAssertFalse(values[replacement...].contains(where: { $0.verificationMessage == "outer" })) }
        }
        withExtendedLifetime((first, next)) {}
    }
    func testVerificationResponseForOriginalEpochCannotAffectNewOwner() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let ticket = try XCTUnwrap(state.beginVerification(context: context))
        XCTAssertEqual(state.snapshot.verificationStatus, .sending)
        _ = state.adopt(session("B"))
        XCTAssertFalse(state.finishVerification(ticket: ticket, message: "old sent"))
        XCTAssertNil(state.snapshot.verificationMessage); XCTAssertEqual(state.snapshot.verificationStatus, .idle)
    }
    func testRunningVerificationRejectsAnotherActionUntilOriginalResponseFinishes() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let first = try XCTUnwrap(state.beginVerification(context: context))
        XCTAssertNil(state.beginVerification(context: context)); XCTAssertNil(state.beginRefresh(context: context))
        XCTAssertTrue(state.finishVerification(ticket: first, message: "first sent"))
        let second = try XCTUnwrap(state.beginVerification(context: context))
        XCTAssertFalse(state.finishVerification(ticket: first, message: "old"))
        XCTAssertTrue(state.finishVerification(ticket: second, message: "sent"))
        XCTAssertEqual(state.snapshot.verificationMessage, "sent")
        XCTAssertFalse(state.finishVerification(ticket: second, message: "duplicate"))
    }
    func testRunningRefreshRejectsVerificationAndAnotherRefreshUntilActualCompletion() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let first = try XCTUnwrap(state.beginRefresh(context: context))
        XCTAssertNil(state.beginRefresh(context: context)); XCTAssertNil(state.beginVerification(context: context))
        XCTAssertTrue(state.failRefresh(ticket: first, message: "offline"))
        XCTAssertNotNil(state.beginVerification(context: context))
    }
    func testVerifiedAccountCannotSendVerificationAndCanonicalVerificationClearsOldFeedback() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let ticket = try XCTUnwrap(state.beginVerification(context: context))
        _ = state.finishVerification(ticket: ticket, message: "sent")
        _ = state.adopt(session(verified: true))
        XCTAssertNil(state.snapshot.verificationMessage)
        XCTAssertNil(state.beginVerification(context: context))
    }
    func testRefreshAcceptsOnlyOriginalOwnerAndPublishesOneCoherentVerifiedSnapshot() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let ticket = try XCTUnwrap(state.beginRefresh(context: context))
        XCTAssertFalse(state.acceptRefresh(session("B", verified: true), ticket: ticket))
        XCTAssertTrue(state.isCurrent(ticket)); XCTAssertFalse(state.snapshot.session!.isEmailVerified)
        XCTAssertTrue(state.acceptRefresh(session(verified: true), ticket: ticket))
        XCTAssertEqual(state.snapshot.context, .account("A")); XCTAssertTrue(state.snapshot.session!.isEmailVerified)
        XCTAssertEqual(state.snapshot.verificationStatus, .idle); XCTAssertNil(state.snapshot.verificationMessage)
        XCTAssertTrue(state.isCurrent(context)); XCTAssertFalse(state.isCurrent(ticket))
    }
    func testUnverifiedRefreshAndRefreshErrorKeepOriginalSessionWithHonestScopedFeedback() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let first = try XCTUnwrap(state.beginRefresh(context: context))
        XCTAssertTrue(state.acceptRefresh(session(), ticket: first))
        XCTAssertNotNil(state.snapshot.verificationMessage)
        let second = try XCTUnwrap(state.beginRefresh(context: context))
        XCTAssertNil(state.snapshot.verificationMessage)
        XCTAssertTrue(state.failRefresh(ticket: second, message: "offline"))
        XCTAssertEqual(state.snapshot.session, session()); XCTAssertEqual(state.snapshot.verificationMessage, "offline")
        XCTAssertFalse(state.failRefresh(ticket: second, message: "duplicate"))
    }
    func testRefreshWillChangeCannotOverwriteNestedNewEpochWithSameUID() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let ticket = try XCTUnwrap(state.beginRefresh(context: context)); var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.adopt(nil); _ = state.adopt(self.session()) }
        }
        XCTAssertFalse(state.acceptRefresh(session(verified: true), ticket: ticket))
        XCTAssertFalse(state.snapshot.session!.isEmailVerified); XCTAssertFalse(state.isCurrent(context))
        withExtendedLifetime(subscription) {}
    }
    func testForeignModelTicketsCannotAuthorizeVerificationRefreshOrProviderResponse() throws {
        let first = CanonicalSessionState(), second = CanonicalSessionState()
        let context = try XCTUnwrap(first.adopt(session())); _ = second.adopt(session())
        XCTAssertFalse(second.isCurrent(context)); XCTAssertNil(second.beginVerification(context: context))
        XCTAssertNil(second.beginRefresh(context: context)); XCTAssertNil(second.acceptedSession(session(), ticket: context))
    }
    func testRepeatedUnchangedCanonicalSnapshotIsIdempotentAndForcedEpochRevokesActions() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session())); let initial = state.snapshot
        XCTAssertEqual(state.adopt(session()), context); XCTAssertEqual(state.snapshot, initial)
        let replacement = try XCTUnwrap(state.adopt(session(), forceNewGeneration: true))
        XCTAssertNotEqual(replacement.generation, context.generation); XCTAssertFalse(state.isCurrent(context))
    }
    func testActualCanonicalBridgeRejectsReentrantProviderCompletionAndReturnsNoLaterOwner() {
        let state = CanonicalSessionState(), bridge = CanonicalAccountPublication()
        var actualUID: String? = "A", originalContext: CanonicalSessionState.ContextTicket?
        var once = true
        let subscription = state.objectWillChange.sink {
            if once {
                once = false; actualUID = "B"
                _ = bridge.perform(expectedUserID: "B", currentUserID: { actualUID }, steps: [{ _ = state.adopt(self.session("B")) }])
            }
        }
        let accepted = bridge.perform(expectedUserID: "A", currentUserID: { actualUID }, steps: [{ originalContext = state.adopt(self.session()) }])
        XCTAssertFalse(accepted); XCTAssertNil(originalContext); XCTAssertEqual(state.snapshot.userID, "B")
        withExtendedLifetime(subscription) {}
    }
    func testUnavailableProviderSlotReportsHonestFeedbackWithoutCreatingWorkOrBlockingRetry() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        XCTAssertTrue(state.reportUnavailableAction(context: context, message: "En tidligere anmodning afsluttes stadig."))
        XCTAssertEqual(state.snapshot.verificationMessage, "En tidligere anmodning afsluttes stadig.")
        XCTAssertEqual(state.snapshot.verificationStatus, .idle)
        let verification = try XCTUnwrap(state.beginVerification(context: context))
        XCTAssertNil(state.snapshot.verificationMessage)
        XCTAssertFalse(state.reportUnavailableAction(context: context, message: "must not overwrite active action"))
        XCTAssertTrue(state.isCurrent(verification))
    }
    func testUnavailableFeedbackCannotFollowOriginalOwnerThroughGuestAndSameUIDReturn() throws {
        let state = CanonicalSessionState(); let original = try XCTUnwrap(state.adopt(session()))
        _ = state.adopt(nil); _ = state.adopt(session())
        XCTAssertFalse(state.reportUnavailableAction(context: original, message: "old busy"))
        XCTAssertNil(state.snapshot.verificationMessage)
    }
    func testUnavailableFeedbackWillChangeReentryCannotOverwriteReplacementAccount() throws {
        let state = CanonicalSessionState(); let original = try XCTUnwrap(state.adopt(session())); var once = true
        let subscription = state.objectWillChange.sink {
            if once { once = false; _ = state.adopt(self.session("B")) }
        }
        XCTAssertFalse(state.reportUnavailableAction(context: original, message: "old busy"))
        XCTAssertEqual(state.snapshot.userID, "B"); XCTAssertNil(state.snapshot.verificationMessage)
        withExtendedLifetime(subscription) {}
    }
    func testAdoptionValidatorRunsBeforeIdempotentReturnAndCanRejectWithoutPublishing() throws {
        let state = CanonicalSessionState(); _ = try XCTUnwrap(state.adopt(session())); let before = state.snapshot
        XCTAssertNil(state.adopt(session(), stillPermitted: { false }))
        XCTAssertEqual(state.snapshot, before)
    }
    func testFirstValidatorReentryCannotReturnAnUnrelatedNewOwnersContextForOriginalProvider() {
        let state = CanonicalSessionState(); var once = true
        let result = state.adopt(session(), stillPermitted: {
            if once { once = false; _ = state.adopt(self.session("B")) }
            return true
        })
        XCTAssertNil(result); XCTAssertEqual(state.snapshot.userID, "B")
    }
    func testIdempotentAdoptionValidatorReentryAlsoRetainsNewerOwner() {
        let state = CanonicalSessionState(); _ = state.adopt(session()); var once = true
        XCTAssertNil(state.adopt(session(), stillPermitted: {
            if once { once = false; _ = state.adopt(self.session("B")) }
            return true
        }))
        XCTAssertEqual(state.snapshot.userID, "B")
    }
    func testValidatorAfterWillChangeCanDenyCanonicalAssignmentWithoutACompetingCanonicalMutation() {
        let state = CanonicalSessionState(); _ = state.adopt(session()); let before = state.snapshot
        var permitted = true
        let subscription = state.objectWillChange.sink { permitted = false }
        XCTAssertNil(state.adopt(session("B"), stillPermitted: { permitted }))
        XCTAssertEqual(state.snapshot, before)
        withExtendedLifetime(subscription) {}
    }
    func testAfterWillChangeValidatorReentryMustRecheckOwnOperationBeforeAssignment() {
        let state = CanonicalSessionState(); _ = state.adopt(session()); var notified = false, once = true
        let subscription = state.objectWillChange.sink { notified = true }
        XCTAssertNil(state.adopt(session("B"), stillPermitted: {
            if notified, once { once = false; _ = state.adopt(self.session("C")) }
            return true
        }))
        XCTAssertEqual(state.snapshot.userID, "C")
        withExtendedLifetime(subscription) {}
    }
    func testSuspensionValidatorReentryAndRevocationRejectBeforeUnresolvedAssignment() {
        let state = CanonicalSessionState(); _ = state.adopt(session()); let before = state.snapshot
        var permitted = true
        let subscription = state.objectWillChange.sink { permitted = false }
        XCTAssertNil(state.suspend(stillPermitted: { permitted })); XCTAssertEqual(state.snapshot, before)
        withExtendedLifetime(subscription) {}
        let other = CanonicalSessionState(); _ = other.adopt(session()); var once = true
        XCTAssertNil(other.suspend(stillPermitted: {
            if once { once = false; _ = other.adopt(self.session("B")) }
            return true
        }))
        XCTAssertEqual(other.snapshot.userID, "B")
    }
    func testSameOwnerVerifiedCanonicalListenerPreservesOriginalRefreshUntilFinalTokenResult() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let refresh = try XCTUnwrap(state.beginRefresh(context: context))
        _ = state.adopt(session(verified: true))
        XCTAssertTrue(state.isCurrent(context)); XCTAssertTrue(state.isCurrent(refresh))
        XCTAssertEqual(state.snapshot.verificationStatus, .refreshing); XCTAssertNil(state.snapshot.verificationMessage)
        XCTAssertTrue(state.acceptRefresh(session(verified: true), ticket: refresh))
        XCTAssertEqual(state.snapshot.verificationStatus, .idle); XCTAssertFalse(state.isCurrent(refresh))
    }
    func testVerifiedListenerInNewSameUIDEpochCannotReviveOriginalRefresh() throws {
        let state = CanonicalSessionState(); let context = try XCTUnwrap(state.adopt(session()))
        let refresh = try XCTUnwrap(state.beginRefresh(context: context))
        _ = state.adopt(nil); _ = state.adopt(session(verified: true))
        XCTAssertFalse(state.isCurrent(context)); XCTAssertFalse(state.isCurrent(refresh))
        XCTAssertFalse(state.acceptRefresh(session(verified: true), ticket: refresh))
    }
}
