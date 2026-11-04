import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class ReaderEmailReauthenticationPromptTests: XCTestCase {
    private typealias Prompt = ReaderEmailReauthenticationPrompt
    private typealias Coordinator = ReaderAccountDeletionCoordinator
    private enum Fault: Error { case rejected }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        lazy var prompt = Prompt(canonical: canonical)
        var allowed = true, cancelCalls = 0, retryCalls = 0
        var currentHook: (@MainActor () -> Void)?
        var cancelHook: (@MainActor () -> Void)?, retryHook: (@MainActor () -> Bool)?
        init() { _ = canonical.adopt(.init(uid: "reader_a", email: "original@example.invalid", isEmailVerified: false)) }
        func action() async throws -> Coordinator.ActionTicket {
            var captured: Coordinator.ActionTicket?
            let done = XCTestExpectation(description: "Actual coordinator captured original action")
            let coordinator = Coordinator(canonical: canonical, currentMembershipEpoch: { _ in 4 },
                reauthenticate: { action in
                    captured = action
                    return .init(action: action, authenticatedUID: "reader_a", authTimeMs: 100_000, kind: .reauthenticated)
                }, send: { request, _ in
                    let data = try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
                        "scope": ReaderAccountDeletionContract.scope, "status": "pending", "accountDeletionComplete": false,
                        "unresolved": ReaderAccountDeletionContract.unresolved])
                    done.fulfill(); return data
                }, nowMilliseconds: { 100_123 }, scheduleTimeout: { _, _ in {} })
            XCTAssertTrue(coordinator.begin(context: canonical.contextTicket(), membershipEpoch: 4, userConfirmed: true))
            let result = await XCTWaiter.fulfillment(of: [done], timeout: 3); XCTAssertEqual(result, .completed)
            withExtendedLifetime(coordinator) {}
            return try XCTUnwrap(captured)
        }
        func request(_ action: Coordinator.ActionTicket, email: String = "original@example.invalid") async throws -> String {
            try await prompt.request(action: action, email: email, isCurrent: { [unowned self] in
                self.currentHook?(); return self.allowed
            }, onCancel: { [unowned self] in self.cancelCalls += 1; self.cancelHook?() },
                onRetry: { [unowned self] in self.retryCalls += 1; return self.retryHook?() ?? true })
        }
        func open(_ action: Coordinator.ActionTicket) async -> Task<String, Error> {
            let shown = XCTestExpectation(description: "Original password presentation")
            var observed = false
            let observation = prompt.objectWillChange.sink { [unowned self] in
                guard !observed, self.prompt.presentation?.action == action else { return }
                observed = true; shown.fulfill()
            }
            let task = Task { try await self.request(action) }
            let result = await XCTWaiter.fulfillment(of: [shown], timeout: 3); XCTAssertEqual(result, .completed)
            withExtendedLifetime(observation) {}
            return task
        }
        func roundTrip() {
            _ = canonical.adopt(.init(uid: "reader_b", email: "other@example.invalid", isEmailVerified: false))
            _ = canonical.adopt(.init(uid: "reader_a", email: "original@example.invalid", isEmailVerified: false))
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected cancelled original wait", file: file, line: line) } catch {}
    }

    func testReauthPurposeIsImmutableLocksCapturedEmailAndAlwaysUsesSignInValidation() async throws {
        var payload: EmailAccountForm?, selected: EmailAccountAction?
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid"), capture: { action, fields in
            selected = action; payload = fields
            return .init(perform: { ReaderAccountSession(uid: "not-a-login", email: "other@example.invalid", isEmailVerified: true) })
        })
        form.action = .signUp
        form.form = .init(email: "changed-invalid", password: "x", confirmation: "different", displayName: "Ignored")
        let submission = try XCTUnwrap(form.captureSubmission())
        XCTAssertEqual(selected, .signIn); XCTAssertEqual(payload?.email, "original@example.invalid")
        XCTAssertEqual(payload?.password, "x"); XCTAssertTrue(form.form.password.isEmpty); XCTAssertTrue(form.form.confirmation.isEmpty)
        await form.submit(submission)
        XCTAssertTrue(form.isReauthentication); XCTAssertEqual(form.lockedEmail, "original@example.invalid")
        XCTAssertNil(form.authenticatedSession); XCTAssertNil(form.statusMessage); XCTAssertFalse(form.isWorking)
    }
    func testReauthCannotTurnPasswordConfirmationIntoPasswordResetOrAccountCreation() async {
        var calls = 0
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid")) { _, _ in calls += 1; return nil }
        form.action = .resetPassword; form.form.confirmation = "unused"
        XCTAssertNil(form.captureSubmission()); XCTAssertEqual(calls, 0)
        XCTAssertEqual(form.errorMessage, "Skriv din adgangskode.")
        XCTAssertTrue(form.form.password.isEmpty); XCTAssertTrue(form.form.confirmation.isEmpty); XCTAssertNil(form.statusMessage)
    }
    func testReauthCaptureFailureClearsPasswordsAndUsesNeutralConfirmationError() {
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid"), capture: { _, _ in
            throw NSError(domain: "private-provider", code: 17009, userInfo: [NSLocalizedDescriptionKey: "PRIVATE provider detail"])
        })
        form.form.password = "inert-fixture"; form.form.confirmation = "inert-fixture"
        XCTAssertNil(form.captureSubmission()); XCTAssertTrue(form.form.password.isEmpty); XCTAssertTrue(form.form.confirmation.isEmpty)
        XCTAssertEqual(form.errorMessage, "Kunne ikke bekræfte din identitet. Prøv igen.")
        XCTAssertFalse(form.isWorking); XCTAssertNil(form.authenticatedSession)
    }
    func testIdleReauthCancellationClearsUnsubmittedDraftAndIsReentrant() {
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid")) { _, _ in nil }
        form.form.password = "inert-fixture"; form.form.confirmation = "inert-fixture"
        var publications = 0
        let observation = form.objectWillChange.sink { publications += 1; form.cancel() }
        form.cancel(); form.cancel()
        XCTAssertTrue(form.form.password.isEmpty); XCTAssertTrue(form.form.confirmation.isEmpty)
        XCTAssertEqual(publications, 1); withExtendedLifetime(observation) {}
    }
    func testOldReauthResultDoesNotClearReplacementDraftOrPublishSession() async throws {
        let form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid"), perform: { _, _ in throw Fault.rejected })
        form.form.password = "first-fixture"
        let submission = try XCTUnwrap(form.captureSubmission())
        form.form.password = "replacement-fixture"; form.form.confirmation = "replacement-confirmation"
        await form.submit(submission)
        XCTAssertEqual(form.form.password, "replacement-fixture"); XCTAssertEqual(form.form.confirmation, "replacement-confirmation")
        XCTAssertNil(form.authenticatedSession); XCTAssertNil(form.statusMessage)
    }
    func testReauthCancelHookCannotClearNewDraftPublishedByReentry() throws {
        var form: EmailAccountFlowModel!
        form = EmailAccountFlowModel(purpose: .reauthentication(lockedEmail: "original@example.invalid"), capture: { _, _ in
            .init(perform: { nil }, cancel: { form.form.password = "new-draft"; form.form.confirmation = "new-confirmation" })
        })
        form.form.password = "first-fixture"; _ = try XCTUnwrap(form.captureSubmission())
        form.cancel()
        XCTAssertEqual(form.form.password, "new-draft"); XCTAssertEqual(form.form.confirmation, "new-confirmation")
        XCTAssertFalse(form.isWorking)
    }
    func testDefaultAccountFormStillPublishesItsExistingLoginSession() async {
        let session = ReaderAccountSession(uid: "reader_a", email: "original@example.invalid", isEmailVerified: false)
        let form = EmailAccountFlowModel { action, _ in XCTAssertEqual(action, .signIn); return session }
        form.form.email = session.email; form.form.password = "inert-fixture"
        await form.submit()
        XCTAssertFalse(form.isReauthentication); XCTAssertNil(form.lockedEmail); XCTAssertEqual(form.authenticatedSession, session)
    }

    func testPromptConstructionIsInertAndWaitsForActualFormSubmission() async throws {
        let f = Fixture(); XCTAssertNil(f.prompt.presentation)
        let action = try await f.action(), provider = await f.open(action)
        let shown = try XCTUnwrap(f.prompt.presentation)
        XCTAssertEqual(shown.id, action.actionID); XCTAssertEqual(shown.action, action); XCTAssertEqual(shown.email, "original@example.invalid")
        XCTAssertEqual(shown.state, .waitingPassword); XCTAssertFalse(shown.form.isWorking)
        XCTAssertEqual(shown.form.lockedEmail, shown.email); XCTAssertTrue(shown.form.form.password.isEmpty)
        f.prompt.cancel(action: action); await rejected { try await provider.value }
    }
    func testPasswordDeliveryDoesNotCompleteFormBeforeActualSDKOutcome() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()); XCTAssertTrue(form.form.password.isEmpty)
        let submitting = Task { await form.submit(submission) }
        let password = try await provider.value; XCTAssertEqual(password, "inert-fixture")
        XCTAssertEqual(f.prompt.presentation?.state, .verifying); XCTAssertTrue(form.isWorking)
        XCTAssertNil(form.authenticatedSession); XCTAssertNil(form.statusMessage)
        XCTAssertNil(form.captureSubmission())
        f.prompt.complete(action: action); await submitting.value
        XCTAssertNil(f.prompt.presentation); XCTAssertFalse(form.isWorking); XCTAssertNil(form.authenticatedSession)
        f.prompt.cancel(action: action); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testPromptCancelBeforeScheduledSubmitClearsCapturedSecretAndBothWaits() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission())
        f.prompt.cancel(action: action); f.prompt.cancel(action: action)
        await form.submit(submission); await rejected { try await provider.value }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(form.form.password.isEmpty); XCTAssertFalse(form.isWorking); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testPromptCancellationDuringVerifyingFinishesUIWaitButDoesNotInventSDKCompletion() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value
        f.prompt.cancel(action: action); await submitting.value
        XCTAssertNil(f.prompt.presentation); XCTAssertFalse(form.isWorking); XCTAssertEqual(f.cancelCalls, 1)
        f.prompt.complete(action: action); XCTAssertNil(f.prompt.presentation); XCTAssertNil(form.errorMessage)
    }
    func testWrongPasswordKeepsNeutralFailureAndRequiresExplicitNewActionRetry() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value
        f.prompt.complete(action: action, error: NSError(domain: "private", code: 17009))
        f.allowed = false // The coordinator can now retire activeAction; failed UI remains canonical history.
        await submitting.value
        XCTAssertEqual(f.prompt.presentation?.state, .failed); XCTAssertFalse(form.isWorking)
        XCTAssertEqual(form.errorMessage, "Kunne ikke bekræfte din identitet. Prøv igen.")
        XCTAssertTrue(form.form.password.isEmpty); XCTAssertNil(form.authenticatedSession)
        XCTAssertNil(form.captureSubmission()); XCTAssertEqual(f.retryCalls, 0)
        f.prompt.retry(action: action); f.prompt.retry(action: action)
        XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.retryCalls, 1); XCTAssertEqual(f.cancelCalls, 0)
        f.allowed = true
        let next = try await f.action(), nextProvider = await f.open(next)
        XCTAssertNotEqual(next.actionID, action.actionID); XCTAssertTrue(try XCTUnwrap(f.prompt.presentation?.form).form.password.isEmpty)
        f.prompt.complete(action: action, error: Fault.rejected); f.prompt.cancel(action: action); f.prompt.retry(action: action)
        XCTAssertEqual(f.prompt.presentation?.action, next); XCTAssertEqual(f.retryCalls, 1)
        f.prompt.cancel(action: next); await rejected { try await nextProvider.value }
    }
    func testCanonicalAToBToAImmediatelyCancelsWaitingAndVerifyingOriginals() async throws {
        for submitted in [false, true] {
            let f = Fixture(), action = try await f.action(), provider = await f.open(action)
            let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
            var submissionTask: Task<Void, Never>?
            if submitted {
                let submission = try XCTUnwrap(form.captureSubmission()); submissionTask = Task { await form.submit(submission) }
                _ = try await provider.value
            }
            f.roundTrip()
            XCTAssertNil(f.prompt.presentation); XCTAssertTrue(form.form.password.isEmpty); XCTAssertEqual(f.cancelCalls, 1)
            if let submissionTask { await submissionTask.value } else { await rejected { try await provider.value } }
            f.prompt.complete(action: action, error: Fault.rejected); XCTAssertNil(form.errorMessage)
        }
    }
    func testCancelledProviderTaskWithdrawsIdleDraftWithoutWaitingForSDK() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        provider.cancel(); await rejected { try await provider.value }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(form.form.password.isEmpty); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testInjectedDenialBeforeCaptureWithdrawsProviderAndCannotReviveOldAction() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        f.allowed = false; XCTAssertNil(form.captureSubmission()); await rejected { try await provider.value }
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(form.form.password.isEmpty)
        f.allowed = true; await rejected { try await f.request(action) }; XCTAssertNil(f.prompt.presentation)
    }
    func testReentrantCancelDuringPresentationCannotLeaveAnOrphanedPasswordWait() async throws {
        let f = Fixture(), action = try await f.action()
        let observation = f.prompt.objectWillChange.sink {
            guard f.prompt.presentation?.action == action else { return }; f.prompt.cancel(action: action)
        }
        await rejected { try await f.request(action) }; XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 1)
        withExtendedLifetime(observation) {}
    }
    func testReentrantCancelDuringFailedCompletionCannotResumeOutcomeTwiceOrPublishError() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value
        let observation = f.prompt.objectWillChange.sink {
            if f.prompt.presentation?.state == .failed { f.prompt.cancel(action: action) }
        }
        f.prompt.complete(action: action, error: Fault.rejected); await submitting.value
        XCTAssertNil(f.prompt.presentation); XCTAssertNil(form.errorMessage); XCTAssertFalse(form.isWorking); XCTAssertEqual(f.cancelCalls, 1)
        withExtendedLifetime(observation) {}
    }
    func testSuccessDismissalAndLateOldCallbacksCannotCancelNewPrompt() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value; f.prompt.complete(action: action); await submitting.value
        let next = try await f.action(), nextProvider = await f.open(next)
        f.prompt.cancel(action: action); f.prompt.complete(action: action); f.prompt.retry(action: action)
        XCTAssertEqual(f.prompt.presentation?.action, next); XCTAssertEqual(f.cancelCalls, 0)
        f.prompt.cancel(action: next); await rejected { try await nextProvider.value }
    }
    func testOverlappingRequestsCannotReplaceTheExistingPresentation() async throws {
        let f = Fixture(), first = try await f.action(), provider = await f.open(first)
        let second = try await f.action()
        await rejected { try await f.request(second) }; XCTAssertEqual(f.prompt.presentation?.action, first)
        f.prompt.cancel(action: first); await rejected { try await provider.value }
    }
    func testCompletionMustRevalidateOriginalHeldIdentityBeforeDismissing() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value; f.allowed = false; f.prompt.complete(action: action)
        await submitting.value
        XCTAssertNil(f.prompt.presentation); XCTAssertNil(form.errorMessage); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testRetryRejectedByOccupiedCoordinatorRetainsFailedPromptUntilAccepted() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value; f.prompt.complete(action: action, error: Fault.rejected); await submitting.value
        f.retryHook = { false }; f.prompt.retry(action: action)
        XCTAssertEqual(f.prompt.presentation?.action, action); XCTAssertEqual(f.prompt.presentation?.state, .failed)
        XCTAssertEqual(form.errorMessage, "Kunne ikke bekræfte din identitet. Prøv igen."); XCTAssertTrue(form.form.password.isEmpty)
        f.retryHook = { true }; f.prompt.retry(action: action)
        XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.retryCalls, 2); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testReentrantRetryCannotDuplicateCoordinatorActionOrClearNewerPrompt() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let form = try XCTUnwrap(f.prompt.presentation?.form); form.form.password = "inert-fixture"
        let submission = try XCTUnwrap(form.captureSubmission()), submitting = Task { await form.submit(submission) }
        _ = try await provider.value; f.prompt.complete(action: action, error: Fault.rejected); await submitting.value
        f.retryHook = { f.prompt.retry(action: action); return true }
        f.prompt.retry(action: action); XCTAssertEqual(f.retryCalls, 1); XCTAssertNil(f.prompt.presentation)
        let next = try await f.action(), nextProvider = await f.open(next)
        f.prompt.retry(action: action); XCTAssertEqual(f.prompt.presentation?.action, next); XCTAssertEqual(f.retryCalls, 1)
        f.prompt.cancel(action: next); await rejected { try await nextProvider.value }
    }
}
