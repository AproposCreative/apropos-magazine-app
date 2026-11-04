import XCTest
@testable import Apropos

final class ReaderAccountFlowTests: XCTestCase {
    private func fields() -> EmailAccountForm {
        EmailAccountForm(email: " reader@example.invalid ", password: "pass phrase", confirmation: "pass phrase", displayName: "Reader")
    }

    func testRegistrationChecksEmailPasswordAndConfirmation() {
        var value = fields()
        XCTAssertNil(value.validationMessage(for: .signUp))
        XCTAssertEqual(value.normalizedEmail, "reader@example.invalid")
        value.confirmation = "different"
        XCTAssertNotNil(value.validationMessage(for: .signUp))
        value.password = "short"
        value.confirmation = "short"
        XCTAssertNotNil(value.validationMessage(for: .signUp))
        value.email = "invalid address@example.invalid"
        XCTAssertNotNil(value.validationMessage(for: .resetPassword))
    }

    func testExistingShortPasswordCanStillSignInAndResetNeedsNoPassword() {
        var value = fields()
        value.password = "oldpwd"
        XCTAssertNil(value.validationMessage(for: .signIn))
        value.password = ""
        value.confirmation = ""
        XCTAssertNil(value.validationMessage(for: .resetPassword))
    }

    func testCollisionAndUnknownAccountMessagesDoNotExposeSDKDetails() {
        XCTAssertTrue(AccountErrorMessage.forError(NSError(domain: "Auth", code: 17007)).contains("metode"))
        XCTAssertEqual(AccountErrorMessage.forError(NSError(domain: "Auth", code: 17009)),
                       AccountErrorMessage.forError(NSError(domain: "Auth", code: 17011)))
    }

    @MainActor
    func testInvalidRegistrationNeverCallsTransport() async {
        var calls = 0
        let model = EmailAccountFlowModel { _, _ in calls += 1; return nil }
        model.action = .signUp
        await model.submit()
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    @MainActor
    func testSuccessfulRegistrationClearsPasswordsAndPublishesSession() async {
        let session = ReaderAccountSession(uid: "reader", email: "reader@example.invalid", isEmailVerified: false)
        let model = EmailAccountFlowModel { action, _ in
            XCTAssertEqual(action, .signUp)
            return session
        }
        model.form = fields()
        model.action = .signUp
        await model.submit()
        XCTAssertEqual(model.authenticatedSession, session)
        XCTAssertTrue(model.form.password.isEmpty)
        XCTAssertTrue(model.form.confirmation.isEmpty)
        XCTAssertFalse(model.isWorking)
    }

    @MainActor
    func testResetResponseDoesNotConfirmWhetherAccountExists() async {
        let model = EmailAccountFlowModel { _, _ in nil }
        model.form.email = "reader@example.invalid"
        model.action = .resetPassword
        await model.submit()
        XCTAssertTrue(model.statusMessage?.contains("Hvis adressen") == true)
        XCTAssertNil(model.authenticatedSession)
    }

    @MainActor
    func testFailureAllowsRetryWithoutClaimingAuthentication() async {
        var attempts = 0
        let session = ReaderAccountSession(uid: "reader", email: "reader@example.invalid", isEmailVerified: true)
        let model = EmailAccountFlowModel { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return session
        }
        model.form = fields()
        await model.submit()
        XCTAssertNil(model.authenticatedSession)
        XCTAssertNotNil(model.errorMessage)
        await model.submit()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.authenticatedSession, session)
    }

    @MainActor
    func testRepeatedSubmitDoesNotCreateTwoAccounts() async {
        let fixture = EmailOperationFixture()
        let model = EmailAccountFlowModel { _, _ in await fixture.perform() }
        model.form = fields()
        model.action = .signUp
        let first = Task { await model.submit() }
        await fixture.waitForRequest()
        await model.submit()
        let count = await fixture.requests
        XCTAssertEqual(count, 1)
        await fixture.complete()
        await first.value
        XCTAssertFalse(model.isWorking)
    }
}

private actor EmailOperationFixture {
    private var continuation: CheckedContinuation<ReaderAccountSession?, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var requests = 0
    func perform() async -> ReaderAccountSession? {
        requests += 1
        return await withCheckedContinuation {
            continuation = $0
            observer?.resume(); observer = nil
        }
    }
    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func complete() {
        continuation?.resume(returning: ReaderAccountSession(uid: "reader", email: "reader@example.invalid", isEmailVerified: false))
        continuation = nil
    }
}
