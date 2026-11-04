import Combine
import XCTest
@testable import Apropos

/// Exercises the form/provider models wired by the actual buttons, with the
/// actual admission coordinator and held effects. No provider SDK is started.
@MainActor
final class AuthLoginFlowAdmissionTests: XCTestCase {
    @MainActor private final class Fixture {
        let state = CanonicalSessionState()
        var uid: String?
        var effects = 0
        lazy var gate = AuthOperationCoordinator(canonical: state, actualUserID: { [unowned self] in uid })
        init() { state.adopt(nil) }
        func select(_ uid: String?) {
            self.uid = uid
            state.adopt(uid.map { ReaderAccountSession(uid: $0, email: "reader@example.invalid", isEmailVerified: true) })
        }
        func email(effect: @escaping (EmailAccountForm) async throws -> Void = { _ in }) -> EmailAccountFlowModel {
            EmailAccountFlowModel(capture: { [self] action, fields in
                let kind: AuthOperationCoordinator.Kind = action == .signIn ? .emailSignIn : action == .signUp ? .emailSignUp : .passwordReset
                let ticket = try gate.capture(kind)
                return .init(perform: {
                    try await self.gate.exchange(ticket) { self.effects += 1; try await effect(fields); return nil }
                }, cancel: { self.gate.cancel(ticket) }, feedbackIsCurrent: { self.gate.canPublishFeedback(ticket) })
            })
        }
        func apple(effect: @escaping () async throws -> Void = {}) -> AppleAccountFlowModel {
            AppleAccountFlowModel(capture: { [self] in
                let ticket = try gate.capture(.apple)
                try gate.beginProvider(ticket)
                return .init(perform: { _, _, _ in
                    try await self.gate.exchange(ticket) {
                        self.effects += 1
                        try await effect()
                        self.select("A")
                        let context = self.state.contextTicket()
                        guard self.gate.acceptResult(ticket, context: context) else { return nil }
                        return self.state.snapshot.session
                    }
                }, providerReturned: { try self.gate.providerReturned(ticket) },
                   providerFailed: { self.gate.providerFailed(ticket) }, cancel: { self.gate.cancel(ticket) },
                   feedbackIsCurrent: { self.gate.canPublishFeedback(ticket) })
            })
        }
    }
    @MainActor private final class HeldEffect {
        var continuation: CheckedContinuation<Void, Never>?
        var observer: CheckedContinuation<Void, Never>?
        func run() async {
            await withCheckedContinuation { continuation = $0; observer?.resume(); observer = nil }
        }
        func started() async {
            if continuation != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func finish() { let original = continuation; continuation = nil; original?.resume() }
    }
    private func fill(_ model: EmailAccountFlowModel) {
        model.form = EmailAccountForm(email: "reader@example.invalid", password: "original-password", confirmation: "original-password", displayName: "Reader")
    }
    private func reply(_ challenge: AppleSignInChallenge) -> AppleIdentityResponse {
        .init(identityToken: Data("token".utf8), state: challenge.state, fullName: nil)
    }

    func testEmailButtonCaptureFreezesPayloadBeforeTaskIsScheduled() async throws {
        let fixture = Fixture()
        var received: EmailAccountForm?
        let model = fixture.email { received = $0 }; fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        model.form.email = "different@example.invalid"; model.form.password = "different-password"
        await model.submit(original)
        XCTAssertEqual(received?.normalizedEmail, "reader@example.invalid")
        XCTAssertEqual(received?.password, "original-password")
        XCTAssertEqual(fixture.effects, 1)
        XCTAssertFalse(model.isWorking)
    }

    func testEmailCapturedBeforeAccountChangeCannotStartFirebaseWhenTaskRuns() async throws {
        let fixture = Fixture(), model: EmailAccountFlowModel
        model = fixture.email(); fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        fixture.select("A")
        await model.submit(original)
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertFalse(fixture.gate.isBusy); XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.authenticatedSession)
    }

    func testEmailDismissedBeforeTaskCannotStartFirebaseAndAllowsNewCapture() async throws {
        let fixture = Fixture(), model: EmailAccountFlowModel
        model = fixture.email(); fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        model.cancel()
        await model.submit(original)
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertFalse(fixture.gate.isBusy); XCTAssertFalse(model.isWorking)
        fill(model)
        XCTAssertNotNil(model.captureSubmission())
        model.cancel()
    }

    func testReentrantCancelDuringCapturedFeedbackCannotLeaveEmailBusy() {
        let fixture = Fixture(), model: EmailAccountFlowModel
        model = fixture.email(); fill(model)
        var cancelled = false
        let observation = model.objectWillChange.sink {
            if model.isWorking, !cancelled { cancelled = true; model.cancel() }
        }
        XCTAssertNil(model.captureSubmission())
        XCTAssertTrue(cancelled)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        withExtendedLifetime(observation) {}
    }

    func testFirstEmailFeedbackPublicationCannotRecaptureAChangedGuestGeneration() async throws {
        let fixture = Fixture(), model: EmailAccountFlowModel
        model = fixture.email(); fill(model)
        var changed = false
        let observation = model.objectWillChange.sink {
            guard !changed else { return }
            changed = true
            fixture.select("A"); fixture.select(nil)
        }
        let original = try XCTUnwrap(model.captureSubmission())
        await model.submit(original)
        XCTAssertTrue(changed)
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        withExtendedLifetime(observation) {}
    }

    func testEmailCancellationCanReenterThroughEveryPasswordPublication() throws {
        let fixture = Fixture(), model: EmailAccountFlowModel
        model = fixture.email(); fill(model)
        _ = try XCTUnwrap(model.captureSubmission())
        var callbacks = 0
        let observation = model.objectWillChange.sink {
            callbacks += 1
            model.cancel()
        }
        model.cancel()
        XCTAssertGreaterThan(callbacks, 0)
        XCTAssertLessThan(callbacks, 10)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        XCTAssertTrue(model.form.password.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testEmailCancellationKeepsSharedSlotUntilActualExchangeReturns() async throws {
        let fixture = Fixture(), held = HeldEffect()
        let model = fixture.email { _ in await held.run() }; fill(model)
        let original = try XCTUnwrap(model.captureSubmission())
        let pending = Task { await model.submit(original) }
        await held.started()
        model.cancel()
        XCTAssertTrue(model.isWorking); XCTAssertTrue(fixture.gate.isBusy)
        XCTAssertThrowsError(try fixture.gate.capture(.google))
        held.finish(); await pending.value
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        XCTAssertNil(model.authenticatedSession); XCTAssertNil(model.errorMessage)
    }

    func testAppleOriginalProviderReplyCannotAuthenticateAfterAccountChanged() async throws {
        let fixture = Fixture(), model: AppleAccountFlowModel
        model = fixture.apple()
        let original = try XCTUnwrap(model.begin())
        fixture.select("A")
        await model.complete(ticketID: original.id, response: reply(original))
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        XCTAssertNil(model.authenticatedSession); XCTAssertNil(model.errorMessage)
    }

    func testAppleDismissalAfterProviderReplyBeforeScheduledExchangeBlocksMutation() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime()
        let model = fixture.apple()
        let original = try XCTUnwrap(model.begin())
        let registration = lifetime.register { model.cancel(ticketID: original.id) }
        // The native callback has produced the response but its Task has not run.
        let response = reply(original)
        lifetime.invalidate()
        XCTAssertTrue(fixture.gate.isBusy)
        await model.complete(ticketID: original.id, response: response)
        lifetime.finish(registration)
        XCTAssertEqual(fixture.effects, 0)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        XCTAssertNil(model.errorMessage)
    }

    func testAppleOwnCanonicalCallbackAcceptsReceiptWithoutDismissingSheet() async throws {
        let fixture = Fixture(), lifetime = AccountLoginLifetime()
        let model = fixture.apple()
        let original = try XCTUnwrap(model.begin())
        let registration = lifetime.register { model.cancel(ticketID: original.id) }
        // A canonical guest→account render does not invalidate this lifetime.
        await model.complete(ticketID: original.id, response: reply(original))
        lifetime.finish(registration)
        XCTAssertEqual(model.authenticatedSession?.uid, "A")
        XCTAssertFalse(lifetime.isInvalidated)
        XCTAssertFalse(fixture.gate.isBusy)
        lifetime.invalidate()
        XCTAssertEqual(model.authenticatedSession?.uid, "A")
    }

    func testAppleDismissalDuringActualExchangeDoesNotReleaseSharedSlotEarly() async throws {
        let fixture = Fixture(), held = HeldEffect(), lifetime = AccountLoginLifetime()
        let model = fixture.apple { await held.run() }
        let original = try XCTUnwrap(model.begin())
        let registration = lifetime.register { model.cancel(ticketID: original.id) }
        let pending = Task { await model.complete(ticketID: original.id, response: reply(original)) }
        await held.started()
        lifetime.invalidate()
        XCTAssertTrue(model.isWorking); XCTAssertTrue(fixture.gate.isBusy)
        XCTAssertThrowsError(try fixture.gate.capture(.emailSignIn))
        held.finish(); await pending.value
        lifetime.finish(registration)
        XCTAssertFalse(model.isWorking); XCTAssertFalse(fixture.gate.isBusy)
        XCTAssertNil(model.authenticatedSession); XCTAssertNil(model.errorMessage)
        // An already accepted SDK operation may still change canonical identity.
        XCTAssertEqual(fixture.state.snapshot.session?.uid, "A")
    }

    func testLifetimeInvalidationIsOneShotAndReentrantRegistrationCannotEscape() {
        let lifetime = AccountLoginLifetime()
        var calls: [String] = []
        _ = lifetime.register {
            calls.append("first")
            _ = lifetime.register { calls.append("nested") }
            lifetime.invalidate()
        }
        lifetime.invalidate(); lifetime.invalidate()
        XCTAssertEqual(calls, ["first", "nested"])
        _ = lifetime.register { calls.append("late") }
        XCTAssertEqual(calls, ["first", "nested", "late"])
    }
}
