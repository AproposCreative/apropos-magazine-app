import Foundation
import XCTest
@testable import Apropos

@MainActor
final class AuthOperationCoordinatorTests: XCTestCase {
    @MainActor private final class Fixture {
        let state = CanonicalSessionState()
        var actualUID: String?
        var identityReads = 0
        var onIdentity: (() -> Void)?
        lazy var coordinator = AuthOperationCoordinator(canonical: state, actualUserID: { [unowned self] in
            identityReads += 1
            onIdentity?()
            return actualUID
        })
        @discardableResult func select(_ uid: String?) -> CanonicalSessionState.ContextTicket {
            actualUID = uid
            _ = state.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: true) })
            return state.contextTicket()
        }
    }
    @MainActor private final class Gate {
        private var held: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?
        func hold() async {
            await withCheckedContinuation { continuation in
                held = continuation
                let waiting = observer; observer = nil; waiting?.resume()
            }
        }
        func waitUntilHeld() async {
            if held != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release() {
            let value = held; held = nil; value?.resume()
        }
    }
    private enum FixtureError: Error { case provider }
    private func expectCancellation(_ operation: () async throws -> Void,
                                    file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected stale or cancelled admission to fail", file: file, line: line) }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
    private func assertBusy(_ operation: () throws -> Void,
                            file: StaticString = #filePath, line: UInt = #line) {
        do { try operation(); XCTFail("An actual provider slot must remain occupied", file: file, line: line) }
        catch AuthOperationCoordinator.Failure.busy { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }

    func testNewsletterConsentBelongsOnlyToCapturedAuthenticationAndNotPasswordReset() throws {
        let fixture = Fixture()
        fixture.select(nil)
        let original = try fixture.coordinator.capture(.google, newsletterOptIn: true)
        XCTAssertTrue(original.newsletterOptIn)
        fixture.coordinator.cancel(original)
        let replacement = try fixture.coordinator.capture(.emailSignUp)
        XCTAssertFalse(replacement.newsletterOptIn)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        fixture.coordinator.cancel(replacement)
        let reset = try fixture.coordinator.capture(.passwordReset, newsletterOptIn: true)
        XCTAssertFalse(reset.newsletterOptIn)
    }

    func testConstructionIsInertAndOnlyConfirmedGuestCanCapture() throws {
        let fixture = Fixture()
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertEqual(fixture.identityReads, 0)
        XCTAssertThrowsError(try fixture.coordinator.capture(.google)) { XCTAssertTrue($0 is CancellationError) }
        fixture.select("A")
        XCTAssertThrowsError(try fixture.coordinator.capture(.emailSignIn)) { XCTAssertTrue($0 is CancellationError) }
        fixture.select(nil)
        XCTAssertThrowsError(try fixture.coordinator.capture(.signOut)) { XCTAssertTrue($0 is CancellationError) }
        let ticket = try fixture.coordinator.capture(.apple)
        XCTAssertTrue(fixture.coordinator.isBusy)
        fixture.coordinator.cancel(ticket)
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testCapturedIntentRejectsChangedOwnerBeforeSchedulingAnyExchangeAndReleasesReservation() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignIn)
        fixture.select("A")
        var effects = 0
        await expectCancellation {
            try await fixture.coordinator.exchange(original) { effects += 1 }
        }
        XCTAssertEqual(effects, 0); XCTAssertFalse(fixture.coordinator.isBusy)
        fixture.select(nil)
        let next = try fixture.coordinator.capture(.google)
        fixture.coordinator.cancel(next)
    }

    func testDismissedCapturedIntentCannotStartProviderOrExchange() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google)
        fixture.coordinator.cancel(original)
        var effects = 0
        await expectCancellation {
            try await fixture.coordinator.provider(original) { effects += 1 }
        }
        await expectCancellation {
            try await fixture.coordinator.exchange(original) { effects += 1 }
        }
        XCTAssertEqual(effects, 0); XCTAssertFalse(fixture.coordinator.isBusy)
        let next = try fixture.coordinator.capture(.emailSignUp)
        fixture.coordinator.cancel(next)
    }

    func testGuestToAccountToGuestCannotReviveOriginalCapturedIntent() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.passwordReset)
        fixture.select("A"); fixture.select(nil)
        var effects = 0
        await expectCancellation { try await fixture.coordinator.exchange(original) { effects += 1 } }
        XCTAssertEqual(effects, 0)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testProviderCancellationKeepsActualSlotUntilItsRealReturn() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google), gate = Gate()
        let running = Task { try await fixture.coordinator.provider(original) { await gate.hold(); return "credential" } }
        await gate.waitUntilHeld()
        fixture.coordinator.cancel(original)
        XCTAssertTrue(fixture.coordinator.isBusy)
        assertBusy { _ = try fixture.coordinator.capture(.emailSignIn) }
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        gate.release()
        await expectCancellation { _ = try await running.value }
        XCTAssertFalse(fixture.coordinator.isBusy)
        let next = try fixture.coordinator.capture(.emailSignIn)
        fixture.coordinator.cancel(next)
    }

    func testHeldGoogleCredentialCannotStartExchangeAfterCanonicalOwnerChanges() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google), gate = Gate()
        var exchanges = 0
        let running = Task {
            let credential = try await fixture.coordinator.provider(original) {
                await gate.hold()
                return "original-google-credential"
            }
            return try await fixture.coordinator.exchange(original) {
                exchanges += 1
                return credential
            }
        }
        await gate.waitUntilHeld()
        fixture.select("B")
        XCTAssertTrue(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        gate.release()
        await expectCancellation { _ = try await running.value }
        XCTAssertEqual(exchanges, 0)
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertEqual(fixture.state.snapshot.userID, "B")
        fixture.select(nil)
        let next = try fixture.coordinator.capture(.emailSignIn)
        try await fixture.coordinator.exchange(next) { exchanges += 1 }
        XCTAssertEqual(exchanges, 1)
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testExchangeCancellationKeepsActualSlotUntilItsRealReturn() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignUp), gate = Gate()
        let running = Task { try await fixture.coordinator.exchange(original) { await gate.hold(); return "created" } }
        await gate.waitUntilHeld()
        fixture.coordinator.cancel(original)
        assertBusy { _ = try fixture.coordinator.capture(.apple) }
        XCTAssertTrue(fixture.coordinator.isBusy)
        gate.release()
        await expectCancellation { _ = try await running.value }
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
    }

    func testDuplicateExchangeCannotReleaseOrReplaceTheActualInFlightSlot() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignIn), gate = Gate()
        var effects = 0
        let running = Task { try await fixture.coordinator.exchange(original) { effects += 1; await gate.hold(); return 1 } }
        await gate.waitUntilHeld()
        await expectCancellation { try await fixture.coordinator.exchange(original) { effects += 1 } }
        XCTAssertTrue(fixture.coordinator.isBusy); XCTAssertEqual(effects, 1)
        assertBusy { _ = try fixture.coordinator.capture(.google) }
        gate.release()
        let result = try await running.value
        XCTAssertEqual(result, 1); XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testOwnCanonicalCallbackDuringExchangeCanAcceptTheActualNewAccountReceipt() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.apple)
        let accepted = try await fixture.coordinator.exchange(original) {
            let context = fixture.select("A")
            return fixture.coordinator.acceptResult(original, context: context)
        }
        XCTAssertTrue(accepted)
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(original))
        fixture.select("B")
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
    }

    func testExternalActualUIDMismatchRejectsTheResultReceiptAndFeedback() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google)
        let accepted = try await fixture.coordinator.exchange(original) {
            let context = fixture.select("A")
            fixture.actualUID = "B"
            return fixture.coordinator.acceptResult(original, context: context)
        }
        XCTAssertFalse(accepted)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testSignOutCannotRunWhileProviderIsActuallyOutstanding() throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.apple)
        try fixture.coordinator.beginProvider(original)
        var effects = 0
        assertBusy { try fixture.coordinator.signOut { effects += 1 } }
        fixture.coordinator.cancel(original)
        assertBusy { try fixture.coordinator.signOut { effects += 1 } }
        XCTAssertEqual(effects, 0)
        XCTAssertFalse(fixture.coordinator.providerFailed(original))
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testSignOutCannotRunWhileExchangeIsActuallyOutstanding() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignIn), gate = Gate()
        let running = Task { try await fixture.coordinator.exchange(original) { await gate.hold() } }
        await gate.waitUntilHeld()
        var effects = 0
        assertBusy { try fixture.coordinator.signOut { effects += 1 } }
        XCTAssertEqual(effects, 0)
        gate.release(); try await running.value
        try fixture.coordinator.signOut { effects += 1 }
        XCTAssertEqual(effects, 1); XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testSignOutCancelsMerelyReservedIntentBeforeItsOwnEffect() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignIn)
        var events: [String] = []
        try fixture.coordinator.signOut { events.append("signout") }
        await expectCancellation { try await fixture.coordinator.exchange(original) { events.append("old-login") } }
        XCTAssertEqual(events, ["signout"])
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testReentrantIdentityGetterCannotCaptureAfterAnOwnerRoundTrip() throws {
        let fixture = Fixture(); fixture.select(nil)
        fixture.onIdentity = {
            fixture.onIdentity = nil
            fixture.select("A"); fixture.select(nil)
        }
        XCTAssertThrowsError(try fixture.coordinator.capture(.google)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(fixture.coordinator.isBusy)
        let next = try fixture.coordinator.capture(.apple)
        fixture.coordinator.cancel(next)
    }

    func testReentrantAdmissionCannotStartOldEffectOrReleaseNewReservation() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google)
        var replacement: AuthOperationCoordinator.Ticket?, effects = 0
        fixture.onIdentity = {
            fixture.onIdentity = nil
            fixture.coordinator.cancel(original)
            replacement = try? fixture.coordinator.capture(.emailSignIn)
        }
        await expectCancellation { try await fixture.coordinator.exchange(original) { effects += 1 } }
        XCTAssertEqual(effects, 0)
        XCTAssertTrue(fixture.coordinator.isBusy)
        let next = try XCTUnwrap(replacement)
        try await fixture.coordinator.exchange(next) { effects += 1 }
        XCTAssertEqual(effects, 1); XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testReentrantReceiptIdentityGetterCannotAcceptStaleCanonicalContext() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.emailSignIn)
        let accepted = try await fixture.coordinator.exchange(original) {
            let context = fixture.select("A")
            fixture.onIdentity = { fixture.onIdentity = nil; fixture.select("B") }
            return fixture.coordinator.acceptResult(original, context: context)
        }
        XCTAssertFalse(accepted); XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
    }

    func testFinishedFeedbackCannotReappearAfterNewGuestIntentHasBeenCaptured() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.passwordReset)
        try await fixture.coordinator.exchange(original) { }
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(original))
        let next = try fixture.coordinator.capture(.google)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
        fixture.coordinator.cancel(next)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(original))
    }

    func testCurrentProviderFailureReleasesSlotAndPreservesOriginalError() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let original = try fixture.coordinator.capture(.google)
        do {
            try await fixture.coordinator.provider(original) { throw FixtureError.provider }
            XCTFail("Provider failure must not become success")
        } catch FixtureError.provider { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(original))
    }

    func testAcceptedLoginReceiptBindsOriginalActionNewnessAndExactAcceptedSession() async throws {
        for isNewUser in [false, true] {
            let fixture = Fixture(); let guest = fixture.select(nil)
            let ticket = try fixture.coordinator.capture(.google)
            let session = try await fixture.coordinator.exchange(ticket) {
                let accepted = fixture.select("A")
                XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: accepted, isNewUser: isNewUser))
                let session = try XCTUnwrap(fixture.state.snapshot.session)
                XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session), "Exchange must finish before navigation")
                return session
            }
            let result = try XCTUnwrap(fixture.coordinator.acceptedLoginResult(ticket, session: session))
            XCTAssertEqual(result.originalContext, guest)
            XCTAssertEqual(result.acceptedContext, fixture.state.contextTicket())
            XCTAssertEqual(result.session, session)
            XCTAssertEqual(result.actionID, ticket.actionID)
            XCTAssertEqual(result.isNewUser, isNewUser)
            XCTAssertEqual(fixture.coordinator.acceptedLoginResult(ticket, session: session), result)
        }
    }

    func testUnknownProviderMetadataNeverGuessesNewnessFromAnAcceptedAccount() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.apple)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A")))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(ticket))
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
    }

    func testAcceptedLoginReceiptCannotBeReclassifiedByDuplicateAcceptance() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.emailSignUp)
        let session = try await fixture.coordinator.exchange(ticket) {
            let context = fixture.select("A")
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: context, isNewUser: true))
            XCTAssertFalse(fixture.coordinator.acceptResult(ticket, context: context, isNewUser: false))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        XCTAssertEqual(fixture.coordinator.acceptedLoginResult(ticket, session: session)?.isNewUser, true)
    }

    func testCancelledAcceptedOperationCannotDeliverOnboardingReceipt() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.emailSignUp), gate = Gate()
        let running = Task {
            try await fixture.coordinator.exchange(ticket) {
                XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: true))
                await gate.hold()
            }
        }
        await gate.waitUntilHeld()
        fixture.coordinator.cancel(ticket)
        gate.release()
        await expectCancellation { try await running.value }
        let session = try XCTUnwrap(fixture.state.snapshot.session)
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        XCTAssertEqual(session.uid, "A", "Cancelling navigation does not invent an SDK signout")
    }

    func testFinishedReceiptIsRevokedByDismissalAndCannotBeResurrected() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.apple)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: false))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        XCTAssertNotNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        fixture.coordinator.cancel(ticket)
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
    }

    func testReceiptRejectsOwnerRoundTripAndAReplacementAction() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.google)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: true))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        fixture.select("B"); fixture.select("A")
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        fixture.select(nil)
        let replacement = try fixture.coordinator.capture(.emailSignIn)
        XCTAssertNotEqual(ticket.actionID, replacement.actionID)
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        fixture.coordinator.cancel(replacement)
    }

    func testSameOwnerSessionChangeCannotReplaceOriginalLoginReceipt() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.emailSignIn)
        let original = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: false))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        let changed = ReaderAccountSession(uid: "A", email: "changed@example.invalid", isEmailVerified: true)
        fixture.state.adopt(changed)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(ticket), "Identity epoch can stay the same")
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: original))
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: changed), "Never relabel a different session as the original receipt")
    }

    func testReceiptRechecksAccountAfterReentrantIdentityRead() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.google)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: true))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        fixture.onIdentity = { fixture.onIdentity = nil; fixture.select("B") }
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        XCTAssertEqual(fixture.state.snapshot.userID, "B")
    }

    func testAnotherCoordinatorCannotReturnOriginalLoginReceipt() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.apple)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: true))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        let other = AuthOperationCoordinator(canonical: fixture.state, actualUserID: { "A" })
        XCTAssertNil(other.acceptedLoginResult(ticket, session: session))
    }

    func testPasswordResetCannotManufactureAnAuthenticatedLoginReceipt() async throws {
        let fixture = Fixture(); fixture.select(nil)
        let ticket = try fixture.coordinator.capture(.passwordReset)
        let session = try await fixture.coordinator.exchange(ticket) {
            XCTAssertTrue(fixture.coordinator.acceptResult(ticket, context: fixture.select("A"), isNewUser: true))
            return try XCTUnwrap(fixture.state.snapshot.session)
        }
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
    }

    func testEmailEntryDistinguishesSignInAndCreationWithoutChangingLegacyEntry() {
        XCTAssertEqual(ReaderAccountEntry(topicIDs: [], provider: .email).initialEmailAction, .signUp)
        XCTAssertEqual(ReaderAccountEntry(topicIDs: [], provider: .emailSignUp).initialEmailAction, .signUp)
        XCTAssertEqual(ReaderAccountEntry(topicIDs: [], provider: .emailSignIn).initialEmailAction, .signIn)
        XCTAssertEqual(ReaderAccountEntry(topicIDs: [], provider: .account).initialEmailAction, .signIn)
    }

    func testLoginCaptureNeverIssuesReauthenticationEvenWithNewsletterChoice() throws {
        let fixture = Fixture()
        let owners: [String?] = [nil, "A"]
        for uid in owners {
            fixture.select(uid)
            XCTAssertThrowsError(try fixture.coordinator.capture(.reauthentication, newsletterOptIn: true)) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertFalse(fixture.coordinator.isBusy)
        }
    }

    func testReauthenticationCaptureRequiresCurrentSignedInContextAndActualOwner() throws {
        let fixture = Fixture()
        let unresolved = fixture.state.contextTicket()
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: unresolved))
        let guest = fixture.select(nil)
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: guest))
        let original = fixture.select("A")
        fixture.actualUID = "B"
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: original))
        fixture.actualUID = "A"
        let foreign = CanonicalSessionState()
        _ = foreign.adopt(fixture.state.snapshot.session)
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: foreign.contextTicket()))
        XCTAssertFalse(fixture.coordinator.isBusy)
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        XCTAssertEqual(ticket.kind, .reauthentication)
        XCTAssertEqual(ticket.context, original)
        XCTAssertFalse(ticket.newsletterOptIn)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(ticket))
        fixture.coordinator.cancel(ticket)
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testReauthenticationCannotRecaptureSameUIDAfterNewCanonicalGeneration() throws {
        let fixture = Fixture(); let original = fixture.select("A")
        _ = fixture.state.adopt(fixture.state.snapshot.session, forceNewGeneration: true)
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: original))
        XCTAssertFalse(fixture.coordinator.isBusy)
        let fresh = try fixture.coordinator.captureReauthentication(context: fixture.state.contextTicket())
        XCTAssertNotEqual(original, fresh.context)
        fixture.coordinator.cancel(fresh)
    }

    func testSuccessfulReauthenticationUsesProviderAndExchangeWithoutAnyLoginReceipt() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        let credential = try await fixture.coordinator.provider(ticket) { "fresh-credential" }
        XCTAssertTrue(fixture.coordinator.isBusy, "Provider return reserves the slot for its exchange")
        let result = try await fixture.coordinator.exchange(ticket) {
            XCTAssertEqual(credential, "fresh-credential")
            XCTAssertFalse(fixture.coordinator.acceptResult(ticket, context: original, isNewUser: true))
            return "reauthenticated-original-user"
        }
        XCTAssertEqual(result, "reauthenticated-original-user")
        XCTAssertEqual(fixture.state.contextTicket(), original)
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(ticket))
        let session = try XCTUnwrap(fixture.state.snapshot.session)
        XCTAssertNil(fixture.coordinator.acceptedLoginResult(ticket, session: session))
        XCTAssertFalse(ticket.newsletterOptIn)
    }

    func testReauthenticationProviderRoundTripCannotAdoptSameUIDInNewGeneration() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
        var exchanges = 0
        let running = Task {
            let credential = try await fixture.coordinator.provider(ticket) { await gate.hold(); return "secret" }
            try await fixture.coordinator.exchange(ticket) { exchanges += 1; _ = credential }
        }
        await gate.waitUntilHeld()
        fixture.select(nil); fixture.select("A")
        XCTAssertTrue(fixture.coordinator.isBusy)
        gate.release()
        await expectCancellation { try await running.value }
        XCTAssertEqual(exchanges, 0)
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
    }

    func testReauthenticationExchangeRejectsNewCanonicalGenerationDespiteSameSDKUID() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
        let running = Task {
            try await fixture.coordinator.exchange(ticket) { await gate.hold(); return "fresh-proof" }
        }
        await gate.waitUntilHeld()
        _ = fixture.state.adopt(fixture.state.snapshot.session, forceNewGeneration: true)
        XCTAssertEqual(fixture.actualUID, "A")
        XCTAssertTrue(fixture.coordinator.isBusy)
        gate.release()
        await expectCancellation { _ = try await running.value }
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
    }

    func testReauthenticationExchangeRechecksActualSDKOwnerAfterReturn() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        await expectCancellation {
            _ = try await fixture.coordinator.exchange(ticket) {
                fixture.actualUID = "B"
                return "wrong-user-proof"
            }
        }
        XCTAssertEqual(fixture.state.contextTicket(), original, "The coordinator must not mutate canonical state")
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
    }

    func testReauthenticationProviderCancellationBlocksSignoutAndNewAuthUntilPhysicalReturn() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
        let running = Task { try await fixture.coordinator.provider(ticket) { await gate.hold(); return "credential" } }
        await gate.waitUntilHeld()
        fixture.coordinator.cancel(ticket)
        assertBusy { try fixture.coordinator.signOut { XCTFail("Provider is still physical") } }
        assertBusy { _ = try fixture.coordinator.capture(.google) }
        assertBusy { _ = try fixture.coordinator.captureReauthentication(context: original) }
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
        gate.release()
        await expectCancellation { _ = try await running.value }
        XCTAssertFalse(fixture.coordinator.isBusy)
        let next = try fixture.coordinator.captureReauthentication(context: original)
        XCTAssertNotEqual(next.actionID, ticket.actionID)
        fixture.coordinator.cancel(next)
    }

    func testReauthenticationExchangeCancellationBlocksSignoutAndLoginUntilPhysicalReturn() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
        let running = Task { try await fixture.coordinator.exchange(ticket) { await gate.hold(); return "proof" } }
        await gate.waitUntilHeld()
        fixture.coordinator.cancel(ticket)
        assertBusy { try fixture.coordinator.signOut { XCTFail("Exchange is still physical") } }
        fixture.select(nil)
        assertBusy { _ = try fixture.coordinator.capture(.apple) }
        gate.release()
        await expectCancellation { _ = try await running.value }
        let next = try fixture.coordinator.capture(.apple)
        fixture.coordinator.cancel(next)
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testTaskCancelledReauthenticationNeverStartsProviderOrExchange() async throws {
        for provider in [false, true] {
            let fixture = Fixture(); let original = fixture.select("A")
            let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
            var effects = 0
            let running = Task {
                await gate.hold()
                if provider {
                    try await fixture.coordinator.provider(ticket) { effects += 1 }
                } else {
                    try await fixture.coordinator.exchange(ticket) { effects += 1 }
                }
            }
            await gate.waitUntilHeld()
            running.cancel(); gate.release()
            await expectCancellation { try await running.value }
            XCTAssertEqual(effects, 0)
            XCTAssertFalse(fixture.coordinator.isBusy)
            XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
        }
    }

    func testTaskCancellationDuringReauthenticationKeepsSlotAndRejectsLateValue() async throws {
        for provider in [false, true] {
            let fixture = Fixture(); let original = fixture.select("A")
            let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
            let running = Task {
                if provider {
                    return try await fixture.coordinator.provider(ticket) { await gate.hold(); return "credential" }
                }
                return try await fixture.coordinator.exchange(ticket) { await gate.hold(); return "proof" }
            }
            await gate.waitUntilHeld()
            running.cancel()
            XCTAssertTrue(fixture.coordinator.isBusy)
            assertBusy { try fixture.coordinator.signOut { XCTFail("Cancellation is not a physical return") } }
            gate.release()
            await expectCancellation { _ = try await running.value }
            XCTAssertFalse(fixture.coordinator.isBusy)
            XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
        }
    }

    func testReauthenticationCannotOverlapAnAlreadyOutstandingLogin() async throws {
        for provider in [false, true] {
            let fixture = Fixture(); fixture.select(nil)
            let login = try fixture.coordinator.capture(.google), gate = Gate()
            let running = Task {
                if provider { try await fixture.coordinator.provider(login) { await gate.hold() } }
                else { try await fixture.coordinator.exchange(login) { await gate.hold() } }
            }
            await gate.waitUntilHeld()
            let account = fixture.select("A")
            assertBusy { _ = try fixture.coordinator.captureReauthentication(context: account) }
            fixture.coordinator.cancel(login)
            gate.release()
            await expectCancellation { try await running.value }
            let next = try fixture.coordinator.captureReauthentication(context: account)
            fixture.coordinator.cancel(next)
        }
    }

    func testSignoutCancelsReservedReauthenticationAndCannotBeReenteredByIt() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        var effects = 0
        try fixture.coordinator.signOut {
            effects += 1
            assertBusy { _ = try fixture.coordinator.captureReauthentication(context: original) }
            fixture.select(nil)
        }
        await expectCancellation { try await fixture.coordinator.exchange(ticket) { effects += 10 } }
        XCTAssertEqual(effects, 1)
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
    }

    func testDuplicateReauthenticationExchangeCannotReleasePhysicalSlot() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
        var effects = 0
        let running = Task { try await fixture.coordinator.exchange(ticket) { effects += 1; await gate.hold() } }
        await gate.waitUntilHeld()
        await expectCancellation { try await fixture.coordinator.exchange(ticket) { effects += 10 } }
        XCTAssertTrue(fixture.coordinator.isBusy)
        XCTAssertEqual(effects, 1)
        gate.release(); try await running.value
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testReentrantReauthenticationCaptureCannotSurviveOwnerRoundTrip() throws {
        let fixture = Fixture(); let original = fixture.select("A")
        fixture.onIdentity = {
            fixture.onIdentity = nil
            fixture.select(nil); fixture.select("A")
        }
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: original)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testNestedReauthenticationCaptureCannotBeOverwrittenByOuterCapture() throws {
        let fixture = Fixture(); let original = fixture.select("A")
        var nested: AuthOperationCoordinator.Ticket?
        fixture.onIdentity = {
            fixture.onIdentity = nil
            nested = try? fixture.coordinator.captureReauthentication(context: original)
        }
        XCTAssertThrowsError(try fixture.coordinator.captureReauthentication(context: original)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertTrue(fixture.coordinator.isBusy)
        let accepted = try XCTUnwrap(nested)
        XCTAssertTrue(fixture.coordinator.canPublishFeedback(accepted))
        fixture.coordinator.cancel(accepted)
    }

    func testReentrantReauthenticationAdmissionCannotReleaseAReplacementReservation() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        var nested: AuthOperationCoordinator.Ticket?, effects = 0
        fixture.onIdentity = {
            fixture.onIdentity = nil
            fixture.coordinator.cancel(ticket)
            nested = try? fixture.coordinator.captureReauthentication(context: original)
        }
        await expectCancellation { try await fixture.coordinator.exchange(ticket) { effects += 1 } }
        XCTAssertEqual(effects, 0)
        XCTAssertTrue(fixture.coordinator.isBusy)
        let replacement = try XCTUnwrap(nested)
        try await fixture.coordinator.exchange(replacement) { effects += 1 }
        XCTAssertEqual(effects, 1)
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testReauthenticationCompletionRechecksAfterReentrantIdentityRead() async throws {
        for cancel in [false, true] {
            let fixture = Fixture(); let original = fixture.select("A")
            let ticket = try fixture.coordinator.captureReauthentication(context: original)
            await expectCancellation {
                _ = try await fixture.coordinator.exchange(ticket) {
                    fixture.onIdentity = {
                        fixture.onIdentity = nil
                        if cancel { fixture.coordinator.cancel(ticket) }
                        else { _ = fixture.state.adopt(fixture.state.snapshot.session, forceNewGeneration: true) }
                        XCTAssertTrue(fixture.coordinator.isBusy)
                    }
                    return "fresh-proof"
                }
            }
            XCTAssertFalse(fixture.coordinator.isBusy)
            XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
        }
    }

    func testReauthenticationFailurePreservesOnlyCurrentOwnersError() async throws {
        for provider in [false, true] {
            for changeOwner in [false, true] {
                let fixture = Fixture(); let original = fixture.select("A")
                let ticket = try fixture.coordinator.captureReauthentication(context: original)
                let fail: () async throws -> Void = {
                    if changeOwner { fixture.select("B") }
                    throw FixtureError.provider
                }
                do {
                    if provider { try await fixture.coordinator.provider(ticket, perform: fail) }
                    else { try await fixture.coordinator.exchange(ticket, perform: fail) }
                    XCTFail("A failed provider is not proof")
                } catch is CancellationError { XCTAssertTrue(changeOwner) }
                catch FixtureError.provider { XCTAssertFalse(changeOwner) }
                catch { XCTFail("Unexpected error: \(error)") }
                XCTAssertFalse(fixture.coordinator.isBusy)
                XCTAssertEqual(fixture.coordinator.canPublishFeedback(ticket), !changeOwner)
            }
        }
    }

    func testForeignCoordinatorCannotUseOrCancelOriginalReauthenticationTicket() async throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        let other = AuthOperationCoordinator(canonical: fixture.state, actualUserID: { "A" })
        other.cancel(ticket)
        await expectCancellation { try await other.exchange(ticket) { XCTFail("Foreign exchange must not run") } }
        XCTAssertFalse(other.canPublishFeedback(ticket))
        XCTAssertTrue(fixture.coordinator.isBusy)
        try await fixture.coordinator.exchange(ticket) { }
        XCTAssertFalse(fixture.coordinator.isBusy)
    }

    func testPureCurrentIntentBarrierDoesNotReadInjectedIdentityAndRejectsRevocation() throws {
        let fixture = Fixture(); let original = fixture.select("A")
        let ticket = try fixture.coordinator.captureReauthentication(context: original)
        let reads = fixture.identityReads
        fixture.onIdentity = { XCTFail("The final pure barrier must not reenter injected identity code") }
        XCTAssertTrue(fixture.coordinator.isCurrent(ticket))
        XCTAssertEqual(fixture.identityReads, reads)
        fixture.coordinator.cancel(ticket)
        XCTAssertFalse(fixture.coordinator.isCurrent(ticket))
        fixture.onIdentity = nil
        let next = try fixture.coordinator.captureReauthentication(context: original)
        XCTAssertFalse(fixture.coordinator.isCurrent(ticket))
        fixture.select(nil); fixture.select("A")
        XCTAssertFalse(fixture.coordinator.isCurrent(next))
        fixture.coordinator.cancel(next)
    }

    func testCancelledReauthenticationCannotPublishALateSDKError() async throws {
        for provider in [false, true] {
            let fixture = Fixture(); let original = fixture.select("A")
            let ticket = try fixture.coordinator.captureReauthentication(context: original), gate = Gate()
            let lateFailure: () async throws -> Void = { await gate.hold(); throw FixtureError.provider }
            let running = Task {
                if provider { try await fixture.coordinator.provider(ticket, perform: lateFailure) }
                else { try await fixture.coordinator.exchange(ticket, perform: lateFailure) }
            }
            await gate.waitUntilHeld()
            running.cancel()
            XCTAssertTrue(fixture.coordinator.isBusy)
            gate.release()
            await expectCancellation { try await running.value }
            XCTAssertFalse(fixture.coordinator.isBusy)
            XCTAssertFalse(fixture.coordinator.canPublishFeedback(ticket))
        }
    }
}
