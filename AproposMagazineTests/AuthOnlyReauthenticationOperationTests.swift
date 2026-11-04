import XCTest
@testable import Apropos

@MainActor
final class AuthOnlyReauthenticationOperationTests: XCTestCase {
    private enum Injected: Error { case failed }
    @MainActor private final class Fixture {
        let reader = CanonicalSessionState(), identity = CanonicalSessionState()
        var uid: String? = "reader-A"
        var hook: (() -> Void)?
        lazy var operations = AuthOperationCoordinator(canonical: reader, actualUserID: { [unowned self] in
            hook?(); return uid
        }, reauthenticationIdentity: identity)
        @discardableResult func select(_ uid: String?) -> CanonicalSessionState.ContextTicket {
            self.uid = uid
            let accepted = identity.adopt(uid.map { .init(uid: $0, email: "local@example.invalid", isEmailVerified: true) })
            XCTAssertNotNil(accepted)
            return identity.contextTicket()
        }
    }
    @MainActor private final class Gate {
        var entered = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0; entered = true } }
        func release() { let value = continuation; continuation = nil; value?.resume() }
    }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 { if condition() { return }; try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTFail("Held actual stage was not reached", file: file, line: line)
    }
    private func cancelled(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Old action was accepted", file: file, line: line) }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
    private func busy(_ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        do { try operation(); XCTFail("Physical slot was released early", file: file, line: line) }
        catch AuthOperationCoordinator.Failure.busy { }
        catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }

    func testSecondaryIdentityRequiresExplicitConfigurationAndExactModelBoundContext() throws {
        let f = Fixture(), original = f.select("reader-A")
        let legacy = AuthOperationCoordinator(canonical: f.reader, actualUserID: { f.uid })
        XCTAssertThrowsError(try legacy.captureReauthentication(context: original))
        let foreign = CanonicalSessionState()
        let sameUID = try XCTUnwrap(foreign.adopt(.init(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true)))
        XCTAssertThrowsError(try f.operations.captureReauthentication(context: sameUID))
        let ticket = try f.operations.captureReauthentication(context: original)
        XCTAssertTrue(f.operations.canPublishFeedback(ticket)); XCTAssertEqual(ticket.context, original)
        XCTAssertEqual(f.reader.snapshot.context, .unresolved)
        XCTAssertFalse(ticket.newsletterOptIn); f.operations.cancel(ticket)
    }

    func testSecondaryGuestCannotBecomeReauthenticationOrPrimaryLoginAuthority() {
        let f = Fixture(), guest = f.select(nil)
        XCTAssertThrowsError(try f.operations.captureReauthentication(context: guest))
        XCTAssertThrowsError(try f.operations.capture(.google))
        XCTAssertFalse(f.operations.isBusy)
        XCTAssertEqual(f.reader.snapshot.context, .unresolved)
    }

    func testActualSecondaryProviderAndSDKExchangeReturnNoLoginReceiptOrReaderSession() async throws {
        let f = Fixture(), original = f.select("reader-A")
        let ticket = try f.operations.captureReauthentication(context: original)
        let credential = try await f.operations.provider(ticket) { "fresh-provider-value" }
        let result = try await f.operations.exchange(ticket) {
            XCTAssertEqual(credential, "fresh-provider-value")
            XCTAssertFalse(f.operations.acceptResult(ticket, context: original, isNewUser: true))
            return "confirmed-original-user"
        }
        XCTAssertEqual(result, "confirmed-original-user"); XCTAssertFalse(f.operations.isBusy)
        XCTAssertTrue(f.operations.canPublishFeedback(ticket))
        let session = try XCTUnwrap(f.identity.snapshot.session)
        XCTAssertNil(f.operations.acceptedLoginResult(ticket, session: session))
        XCTAssertEqual(f.reader.snapshot.context, .unresolved)
    }

    func testPrimaryReaderPublicationCannotRebindOrReplaceSecondaryTicket() async throws {
        let f = Fixture(), original = f.select("reader-A")
        let ticket = try f.operations.captureReauthentication(context: original)
        f.reader.adopt(.init(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true))
        f.reader.adopt(.init(uid: "reader-B", email: "local@example.invalid", isEmailVerified: true))
        XCTAssertTrue(f.operations.canPublishFeedback(ticket))
        let result = try await f.operations.exchange(ticket) { 7 }
        XCTAssertEqual(result, 7); XCTAssertEqual(ticket.context, original)
        XCTAssertEqual(f.reader.snapshot.context, .account("reader-B"))
    }

    func testSecondaryRoundTripCannotBeRescuedByPrimarySameUID() async throws {
        let f = Fixture(), original = f.select("reader-A")
        let ticket = try f.operations.captureReauthentication(context: original)
        f.reader.adopt(.init(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true))
        f.select("reader-B"); f.select("reader-A")
        var effects = 0
        await cancelled { try await f.operations.exchange(ticket) { effects += 1 } }
        XCTAssertEqual(effects, 0); XCTAssertFalse(f.operations.canPublishFeedback(ticket))
        XCTAssertFalse(f.operations.isBusy)
    }

    func testCancelledAuthOnlyProviderHoldsSharedSlotAgainstLoginSignoutAndAnotherReauth() async throws {
        let f = Fixture(), original = f.select("reader-A"), gate = Gate()
        let ticket = try f.operations.captureReauthentication(context: original)
        let task = Task { @MainActor in try await f.operations.provider(ticket) { await gate.wait(); return "old" } }
        defer { gate.release() }
        await eventually { gate.entered }; f.operations.cancel(ticket)
        f.reader.adopt(nil); f.uid = nil
        busy { _ = try f.operations.capture(.google) }
        busy { try f.operations.signOut {} }
        busy { _ = try f.operations.captureReauthentication(context: original) }
        gate.release(); await cancelled { _ = try await task.value }
        XCTAssertFalse(f.operations.isBusy)
        let login = try f.operations.capture(.emailSignIn); f.operations.cancel(login)
    }

    func testCancelledAuthOnlySDKExchangeRetainsPhysicalSlotAndRejectsLateSuccess() async throws {
        let f = Fixture(), original = f.select("reader-A"), gate = Gate()
        let ticket = try f.operations.captureReauthentication(context: original)
        let task = Task { @MainActor in try await f.operations.exchange(ticket) { await gate.wait(); return "late" } }
        defer { gate.release() }
        await eventually { gate.entered }; task.cancel()
        XCTAssertTrue(f.operations.isBusy)
        busy { _ = try f.operations.capture(.apple) }
        gate.release(); await cancelled { _ = try await task.value }
        XCTAssertFalse(f.operations.isBusy); XCTAssertFalse(f.operations.canPublishFeedback(ticket))
        XCTAssertEqual(f.reader.snapshot.context, .unresolved)
    }

    func testPrimaryLoginProviderBlocksAuthOnlyReauthenticationUntilItsPhysicalReturn() async throws {
        let f = Fixture(); f.uid = nil; f.reader.adopt(nil)
        let login = try f.operations.capture(.google), gate = Gate()
        let task = Task { @MainActor in try await f.operations.provider(login) { await gate.wait(); return "login" } }
        defer { gate.release() }
        await eventually { gate.entered }
        let authOnly = f.select("reader-A")
        busy { _ = try f.operations.captureReauthentication(context: authOnly) }
        f.operations.cancel(login); gate.release()
        await cancelled { _ = try await task.value }
        let reauth = try f.operations.captureReauthentication(context: authOnly)
        f.operations.cancel(reauth); XCTAssertFalse(f.operations.isBusy)
    }

    func testCaptureIdentityGetterRoundTripRejectsOriginalContextBeforeProvider() {
        let f = Fixture(), original = f.select("reader-A")
        f.hook = { f.hook = nil; f.select("reader-B"); f.select("reader-A") }
        XCTAssertThrowsError(try f.operations.captureReauthentication(context: original))
        XCTAssertFalse(f.operations.isBusy); XCTAssertEqual(f.reader.snapshot.context, .unresolved)
    }

    func testReentrantCaptureRetainsNewReservationAndOuterFailureCannotCancelIt() throws {
        let f = Fixture(), original = f.select("reader-A")
        var replacement: AuthOperationCoordinator.Ticket?
        f.hook = {
            f.hook = nil
            replacement = try? f.operations.captureReauthentication(context: original)
        }
        XCTAssertThrowsError(try f.operations.captureReauthentication(context: original))
        let fresh = try XCTUnwrap(replacement)
        XCTAssertTrue(f.operations.isBusy); XCTAssertTrue(f.operations.canPublishFeedback(fresh))
        f.operations.cancel(fresh); XCTAssertFalse(f.operations.isBusy)
    }

    func testLateProviderErrorAfterSecondaryRoundTripIsCancellationAndKeepsPrimaryUntouched() async throws {
        let f = Fixture(), original = f.select("reader-A"), gate = Gate()
        let ticket = try f.operations.captureReauthentication(context: original)
        let task = Task<String, Error> { @MainActor in
            try await f.operations.provider(ticket) { await gate.wait(); throw Injected.failed }
        }
        defer { gate.release() }
        await eventually { gate.entered }; f.select("reader-B"); f.select("reader-A")
        XCTAssertTrue(f.operations.isBusy)
        gate.release(); await cancelled { _ = try await task.value }
        XCTAssertEqual(f.reader.snapshot.context, .unresolved); XCTAssertFalse(f.operations.isBusy)
    }

    func testNormalLoginStillRequiresAndPublishesOnlyPrimaryReaderContext() async throws {
        let f = Fixture(); f.uid = nil; f.reader.adopt(nil); f.identity.adopt(nil)
        let ticket = try f.operations.capture(.emailSignIn)
        let session = ReaderAccountSession(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true)
        try await f.operations.exchange(ticket) {
            f.uid = session.uid
            let authOnly = try XCTUnwrap(f.identity.adopt(session))
            XCTAssertFalse(f.operations.acceptResult(ticket, context: authOnly, isNewUser: false))
            let reader = try XCTUnwrap(f.reader.adopt(session))
            XCTAssertTrue(f.operations.acceptResult(ticket, context: reader, isNewUser: false))
        }
        let result = try XCTUnwrap(f.operations.acceptedLoginResult(ticket, session: session))
        XCTAssertEqual(result.acceptedContext, f.reader.contextTicket())
        XCTAssertNotEqual(result.acceptedContext, f.identity.contextTicket())
    }

    func testSecondaryReauthDoesNotAuthorizeSubsequentSignoutWithoutSharedSlotDrain() throws {
        let f = Fixture(), original = f.select("reader-A")
        let ticket = try f.operations.captureReauthentication(context: original)
        try f.operations.beginProvider(ticket)
        var signouts = 0
        busy { try f.operations.signOut { signouts += 1 } }
        XCTAssertEqual(signouts, 0)
        f.operations.cancel(ticket); XCTAssertFalse(f.operations.providerFailed(ticket))
        try f.operations.signOut { signouts += 1; f.uid = nil; f.reader.adopt(nil) }
        XCTAssertEqual(signouts, 1); XCTAssertEqual(f.reader.snapshot.context, .guest)
        XCTAssertEqual(f.identity.snapshot.context, .account("reader-A"))
    }
}
