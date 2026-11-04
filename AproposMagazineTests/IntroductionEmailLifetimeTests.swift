import Foundation
import XCTest
@testable import Apropos

@MainActor
final class IntroductionEmailLifetimeTests: XCTestCase {
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var uid: String?
        var captures = 0, effects = 0, cancellations = 0, deliveries = 0
        var capturedFields: EmailAccountForm?
        var onCaptured: (() -> Void)?
        var onCancelled: (() -> Void)?
        lazy var auth = AuthOperationCoordinator(canonical: canonical, actualUserID: { [unowned self] in uid })
        init() { canonical.adopt(nil) }
        func model(lifetime: AccountLoginLifetime,
                   effect: @escaping (EmailAccountForm) async throws -> ReaderAccountSession? = { _ in nil }) -> EmailAccountFlowModel {
            EmailAccountFlowModel(capture: { [self] action, fields in
                try lifetime.captureEmailOperation {
                    captures += 1; capturedFields = fields
                    let kind: AuthOperationCoordinator.Kind = action == .signIn ? .emailSignIn
                        : action == .signUp ? .emailSignUp : .passwordReset
                    let ticket = try auth.capture(kind)
                    onCaptured?()
                    return .init(perform: { [self] in
                        let result = try await auth.exchange(ticket) {
                            self.effects += 1
                            let value = try await effect(fields)
                            if let value {
                                self.uid = value.uid; self.canonical.adopt(value)
                                _ = self.auth.acceptResult(ticket, context: self.canonical.contextTicket(), isNewUser: false)
                            }
                            return value
                        }
                        guard !lifetime.isInvalidated else { throw CancellationError() }
                        if let result, auth.acceptedLoginResult(ticket, session: result) != nil,
                           !lifetime.isInvalidated { deliveries += 1 }
                        return result
                    }, cancel: { [self] in
                        cancellations += 1; auth.cancel(ticket); onCancelled?()
                    }, feedbackIsCurrent: { [self] in auth.canPublishFeedback(ticket) })
                }
            })
        }
    }
    @MainActor private final class HeldReply {
        var continuation: CheckedContinuation<ReaderAccountSession?, Error>?
        var observer: CheckedContinuation<Void, Never>?
        func run() async throws -> ReaderAccountSession? {
            try await withCheckedThrowingContinuation {
                continuation = $0; observer?.resume(); observer = nil
            }
        }
        func started() async {
            if continuation != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func finish(_ result: Result<ReaderAccountSession?, Error>) {
            let original = continuation; continuation = nil; original?.resume(with: result)
        }
    }
    private func fill(_ model: EmailAccountFlowModel, action: EmailAccountAction = .signIn) {
        model.action = action
        model.form = .init(email: "reader@example.invalid", password: "original-password",
                           confirmation: "original-password", displayName: "Reader")
    }
    private var session: ReaderAccountSession {
        .init(uid: "reader-a", email: "reader@example.invalid", isEmailVerified: true)
    }

    func testClosedLifetimeRejectsSignInAndResetBeforeAuthCapture() {
        for action in [EmailAccountAction.signIn, .resetPassword] {
            let fixture = Fixture(), lifetime = AccountLoginLifetime()
            let model = fixture.model(lifetime: lifetime); fill(model, action: action)
            lifetime.invalidate()
            XCTAssertNil(model.captureSubmission())
            XCTAssertEqual(fixture.captures, 0); XCTAssertEqual(fixture.effects, 0)
            XCTAssertEqual(fixture.cancellations, 0); XCTAssertFalse(fixture.auth.isBusy)
            XCTAssertNil(model.errorMessage); XCTAssertNil(model.statusMessage)
        }
    }

    func testReentrantIntroductionDenialAfterAuthCaptureCancelsOnlyOriginalAndNeverPerforms() {
        let fixture = Fixture(), lifetime = AccountLoginLifetime()
        fixture.onCaptured = { lifetime.invalidate() }
        let model = fixture.model(lifetime: lifetime); fill(model)
        XCTAssertNil(model.captureSubmission())
        XCTAssertEqual(fixture.captures, 1); XCTAssertEqual(fixture.cancellations, 1)
        XCTAssertEqual(fixture.effects, 0); XCTAssertFalse(fixture.auth.isBusy)
        lifetime.invalidate(); model.cancel()
        XCTAssertEqual(fixture.cancellations, 1)
    }

    func testCapturedEmailCannotStartAfterParentInvalidatesBeforeTask() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime()
        let model = fixture.model(lifetime: lifetime); fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        XCTAssertTrue(fixture.auth.isBusy)
        lifetime.invalidate()
        await model.submit(original)
        XCTAssertEqual(fixture.effects, 0); XCTAssertEqual(fixture.cancellations, 1)
        XCTAssertFalse(fixture.auth.isBusy); XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.authenticatedSession); XCTAssertNil(model.errorMessage)
    }

    func testLatePhysicalSuccessAfterInvalidationKeepsAuthSlotUntilReturnWithoutDelivery() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime(), held = HeldReply()
        let model = fixture.model(lifetime: lifetime) { _ in try await held.run() }; fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        let task = Task { await model.submit(original) }
        await held.started()
        lifetime.invalidate(); task.cancel()
        XCTAssertTrue(model.isWorking); XCTAssertTrue(fixture.auth.isBusy)
        XCTAssertThrowsError(try fixture.auth.capture(.emailSignIn))
        held.finish(.success(session)); await task.value
        XCTAssertEqual(fixture.effects, 1); XCTAssertEqual(fixture.cancellations, 1)
        XCTAssertEqual(fixture.deliveries, 0); XCTAssertFalse(fixture.auth.isBusy)
        XCTAssertFalse(model.isWorking); XCTAssertNil(model.authenticatedSession)
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.statusMessage)
        // Physical identity effects are not undone by this presentation guard.
        XCTAssertEqual(fixture.canonical.snapshot.session?.uid, "reader-a")
    }

    func testLatePhysicalErrorAfterInvalidationDoesNotPublishOrReleaseSlotEarly() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime(), held = HeldReply()
        let model = fixture.model(lifetime: lifetime) { _ in try await held.run() }; fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        let task = Task { await model.submit(original) }
        await held.started(); lifetime.invalidate(); model.cancel()
        XCTAssertTrue(fixture.auth.isBusy); XCTAssertTrue(model.isWorking)
        held.finish(.failure(NSError(domain: "local.fixture", code: 17009)))
        await task.value
        XCTAssertFalse(fixture.auth.isBusy); XCTAssertFalse(model.isWorking)
        XCTAssertEqual(fixture.cancellations, 1); XCTAssertEqual(fixture.deliveries, 0)
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.authenticatedSession)
    }

    func testNormalSignInKeepsOriginalFieldsAndAcceptedResultAndRetiresRegistration() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime(), accepted = session
        let model = fixture.model(lifetime: lifetime) { _ in accepted }; fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        model.form.email = "changed@example.invalid"; model.form.password = "changed-password"
        await model.submit(original)
        XCTAssertEqual(fixture.capturedFields?.normalizedEmail, "reader@example.invalid")
        XCTAssertEqual(fixture.capturedFields?.password, "original-password")
        XCTAssertEqual(fixture.effects, 1); XCTAssertEqual(fixture.deliveries, 1)
        XCTAssertEqual(model.authenticatedSession, accepted); XCTAssertTrue(model.form.password.isEmpty)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.auth.isBusy)
        lifetime.invalidate()
        XCTAssertEqual(fixture.cancellations, 0, "A returned operation must no longer own a cancellation registration")
    }

    func testNormalResetKeepsNeutralConfirmationAndRetiresRegistration() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime()
        let model = fixture.model(lifetime: lifetime); fill(model, action: .resetPassword)
        let original = try XCTUnwrap(model.captureSubmission())
        await model.submit(original)
        XCTAssertEqual(fixture.effects, 1); XCTAssertEqual(fixture.deliveries, 0)
        XCTAssertNotNil(model.statusMessage); XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.authenticatedSession); XCTAssertFalse(fixture.auth.isBusy)
        lifetime.invalidate(); XCTAssertEqual(fixture.cancellations, 0)
    }

    func testFeedbackHookCannotBorrowPermissionAfterItInvalidatesLifetime() async throws {
        let lifetime = AccountLoginLifetime(), accepted = session
        var feedbackCalls = 0
        let model = EmailAccountFlowModel(capture: { _, _ in
            try lifetime.captureEmailOperation {
                .init(perform: { accepted }, feedbackIsCurrent: {
                    feedbackCalls += 1; lifetime.invalidate(); return true
                })
            }
        })
        fill(model); let original = try XCTUnwrap(model.captureSubmission())
        await model.submit(original)
        XCTAssertEqual(feedbackCalls, 1); XCTAssertNil(model.authenticatedSession)
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.statusMessage)
    }

    func testOriginalCancellationMayCreateNewLifetimeWithoutOldCleanupCancellingIt() async throws {
        let fixture = Fixture(), oldLifetime = AccountLoginLifetime(), newLifetime = AccountLoginLifetime()
        let old = fixture.model(lifetime: oldLifetime); fill(old)
        let original = try XCTUnwrap(old.captureSubmission())
        let replacement = fixture.model(lifetime: newLifetime); fill(replacement, action: .resetPassword)
        var replacementSubmission: EmailAccountFlowModel.Submission?
        fixture.onCancelled = { replacementSubmission = replacement.captureSubmission() }
        oldLifetime.invalidate()
        let fresh = try XCTUnwrap(replacementSubmission)
        XCTAssertTrue(fixture.auth.isBusy); XCTAssertFalse(newLifetime.isInvalidated)
        await old.submit(original)
        XCTAssertTrue(fixture.auth.isBusy); XCTAssertEqual(fixture.effects, 0)
        await replacement.submit(fresh)
        XCTAssertEqual(fixture.effects, 1); XCTAssertEqual(fixture.cancellations, 1)
        XCTAssertNotNil(replacement.statusMessage); XCTAssertFalse(fixture.auth.isBusy)
    }

    func testClosingChildEmailLeavesSameParentAvailableForFreshAttempt() async throws {
        let fixture = Fixture(), parent = AccountLoginLifetime()
        let original = fixture.model(lifetime: parent); fill(original)
        let stale = try XCTUnwrap(original.captureSubmission())
        original.cancel()
        XCTAssertFalse(parent.isInvalidated); XCTAssertFalse(fixture.auth.isBusy)
        let reopened = fixture.model(lifetime: parent); fill(reopened, action: .resetPassword)
        let fresh = try XCTUnwrap(reopened.captureSubmission())
        await original.submit(stale)
        XCTAssertTrue(fixture.auth.isBusy); XCTAssertEqual(fixture.effects, 0)
        await reopened.submit(fresh)
        XCTAssertNotNil(reopened.statusMessage); XCTAssertEqual(fixture.effects, 1)
        XCTAssertEqual(fixture.cancellations, 1); XCTAssertFalse(parent.isInvalidated)
        parent.invalidate(); XCTAssertEqual(fixture.cancellations, 1)
    }

    func testWrappedOperationCannotPerformTwiceAndFinishesOnlyItsRegistration() async throws {
        let lifetime = AccountLoginLifetime()
        var effects = 0, cancellations = 0
        let operation = try lifetime.captureEmailOperation {
            .init(perform: { effects += 1; return nil }, cancel: { cancellations += 1 })
        }
        _ = try await operation.perform()
        do { _ = try await operation.perform(); XCTFail("A captured email operation is single-use") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        operation.cancel(); lifetime.invalidate()
        XCTAssertEqual(effects, 1); XCTAssertEqual(cancellations, 0)
    }
}
