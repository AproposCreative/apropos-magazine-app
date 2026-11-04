import Combine
import FirebaseCore
import XCTest
@testable import Apropos

@MainActor
final class ReaderAppleReauthenticationPromptTests: XCTestCase {
    private typealias Prompt = ReaderAppleReauthenticationPrompt
    private typealias Coordinator = ReaderAccountDeletionCoordinator
    private typealias ProviderTask = Task<Prompt.CredentialValue, Error>
    private enum Fault: Error { case rejected }
    private func challenge() -> AppleSignInChallenge { .init(id: UUID(), rawNonce: "original-nonce", state: "original-state") }
    private func response(_ challenge: AppleSignInChallenge, subject: String? = "original.apple",
                          state: String? = nil, token: Data? = Data("local.identity.token".utf8)) -> AppleIdentityResponse {
        .init(identityToken: token, state: state ?? challenge.state, fullName: nil, userID: subject)
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        lazy var prompt = Prompt(canonical: canonical)
        var allowed = true, providerFinished = false
        var cancelCalls = 0
        var currentHook: (@MainActor () -> Void)?
        init() { _ = canonical.adopt(.init(uid: "reader_a", email: "fixture@example.invalid", isEmailVerified: false)) }
        func action() async throws -> Coordinator.ActionTicket {
            var captured: Coordinator.ActionTicket?
            let done = XCTestExpectation(description: "Original actual coordinator action")
            let coordinator = Coordinator(canonical: canonical, currentMembershipEpoch: { _ in 4 }, reauthenticate: { action in
                captured = action; return .init(action: action, authenticatedUID: "reader_a", authTimeMs: 100_000, kind: .reauthenticated)
            }, send: { request, _ in
                let data = try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "scope": ReaderAccountDeletionContract.scope,
                    "status": "pending", "accountDeletionComplete": false, "unresolved": ReaderAccountDeletionContract.unresolved])
                done.fulfill(); return data
            }, nowMilliseconds: { 100_123 }, scheduleTimeout: { _, _ in {} })
            XCTAssertTrue(coordinator.begin(context: canonical.contextTicket(), membershipEpoch: 4, userConfirmed: true))
            let result = await XCTWaiter.fulfillment(of: [done], timeout: 3); XCTAssertEqual(result, .completed)
            withExtendedLifetime(coordinator) {}; return try XCTUnwrap(captured)
        }
        func request(_ action: Coordinator.ActionTicket, subject: String = "original.apple") async throws -> Prompt.CredentialValue {
            try await prompt.request(action: action, expectedAppleUserID: subject, isCurrent: { [unowned self] in
                self.currentHook?(); return self.allowed
            }, onCancel: { [unowned self] in self.cancelCalls += 1 })
        }
        func open(_ action: Coordinator.ActionTicket) async -> ProviderTask {
            let shown = XCTestExpectation(description: "Original Apple presentation")
            var observed = false
            let observation = prompt.objectWillChange.sink { [unowned self] in
                if !observed, self.prompt.presentation?.action == action { observed = true; shown.fulfill() }
            }
            providerFinished = false
            let task = Task { defer { self.providerFinished = true }; return try await self.request(action) }
            let result = await XCTWaiter.fulfillment(of: [shown], timeout: 3); XCTAssertEqual(result, .completed)
            withExtendedLifetime(observation) {}; return task
        }
        func roundTrip() {
            _ = canonical.adopt(.init(uid: "reader_b", email: "other@example.invalid", isEmailVerified: false))
            _ = canonical.adopt(.init(uid: "reader_a", email: "fixture@example.invalid", isEmailVerified: false))
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected rejection of the original operation", file: file, line: line) } catch {}
    }
    private func drainScheduling() async { for _ in 0..<4 { await Task.yield() } }

    func testReauthenticationSuccessAcceptsNilAndNeverPublishesAnyLoginSession() async throws {
        for returningSession in [false, true] {
            let original = challenge()
            let model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, capture: {
                .init(perform: { _, _, _ in returningSession ? .init(uid: "unexpected", email: "other@example.invalid", isEmailVerified: true) : nil },
                      expectedAppleUserID: "original.apple")
            })
            XCTAssertTrue(model.isReauthentication); XCTAssertNotNil(model.begin())
            await model.complete(ticketID: original.id, response: response(original))
            XCTAssertFalse(model.isWorking); XCTAssertNil(model.authenticatedSession); XCTAssertNil(model.errorMessage)
        }
    }
    func testReauthenticationRequiresCapturedAppleSubjectBeforeAnySDKOperation() async throws {
        let subjects: [String?] = [nil, "foreign.apple", ""]
        for subject in subjects {
            let original = challenge(); var calls = 0, returned = 0
            let model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, capture: {
                .init(perform: { _, _, _ in calls += 1; return nil }, providerReturned: { returned += 1 }, expectedAppleUserID: "original.apple")
            })
            XCTAssertNotNil(model.begin()); await model.complete(ticketID: original.id, response: response(original, subject: subject))
            XCTAssertEqual(calls, 0); XCTAssertEqual(returned, 1); XCTAssertFalse(model.isWorking)
            XCTAssertEqual(model.errorMessage, "Kunne ikke bekræfte din identitet med Apple. Prøv igen.")
        }
    }
    func testReauthenticationWithoutExpectedSubjectFailsClosedButDefaultLoginIsUnchanged() async throws {
        for purpose in [AppleAccountFlowModel.Purpose.login, .reauthentication] {
            let original = challenge(); var calls = 0
            let model = AppleAccountFlowModel(purpose: purpose, makeChallenge: { original }, capture: {
                .init(perform: { _, _, _ in calls += 1; return .init(uid: "reader_a", email: "fixture@example.invalid", isEmailVerified: false) })
            })
            XCTAssertNotNil(model.begin()); await model.complete(ticketID: original.id, response: response(original, subject: nil))
            XCTAssertEqual(calls, purpose == .login ? 1 : 0)
            XCTAssertEqual(model.authenticatedSession?.uid, purpose == .login ? "reader_a" : nil)
        }
    }
    func testReauthenticationSDKErrorUsesNeutralConfirmationMessage() async throws {
        let original = challenge()
        let model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, capture: {
            .init(perform: { _, _, _ in throw NSError(domain: "PRIVATE", code: 17009) }, expectedAppleUserID: "original.apple")
        })
        XCTAssertNotNil(model.begin()); await model.complete(ticketID: original.id, response: response(original))
        XCTAssertNil(model.authenticatedSession); XCTAssertEqual(model.errorMessage, "Kunne ikke bekræfte din identitet med Apple. Prøv igen.")
    }
    func testEmptyReauthenticationChallengeSettlesPreparationBeforeProviderAdmission() {
        for emptyNonce in [true, false] {
            var captured = 0, failed = 0
            let original = AppleSignInChallenge(id: UUID(), rawNonce: emptyNonce ? "" : "nonce", state: emptyNonce ? "state" : "")
            let model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, preparationFailed: { failed += 1 }, capture: {
                captured += 1; return .init(perform: { _, _, _ in nil }, expectedAppleUserID: "original.apple")
            })
            XCTAssertNil(model.begin()); XCTAssertEqual(captured, 0); XCTAssertEqual(failed, 1); XCTAssertFalse(model.isWorking)
        }
    }
    func testCanPresentRequiresExactTicketAndRejectsObservedDenialMonotonically() throws {
        let original = challenge(); var allowed = true, cancelCalls = 0
        let model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, capture: {
            .init(perform: { _, _, _ in nil }, cancel: { cancelCalls += 1 }, feedbackIsCurrent: { allowed }, expectedAppleUserID: "original.apple")
        })
        XCTAssertNotNil(model.begin()); XCTAssertFalse(model.canPresent(ticketID: UUID())); XCTAssertTrue(model.canPresent(ticketID: original.id))
        allowed = false; XCTAssertFalse(model.canPresent(ticketID: original.id)); allowed = true
        XCTAssertFalse(model.canPresent(ticketID: original.id)); XCTAssertTrue(model.isWorking); XCTAssertEqual(cancelCalls, 1)
        model.providerCancelled(ticketID: original.id); XCTAssertFalse(model.isWorking)
    }
    func testCanPresentRechecksAfterOwnershipGetterCancelsOriginalRequest() throws {
        let original = challenge(); var model: AppleAccountFlowModel!, cancellations = 0
        model = AppleAccountFlowModel(purpose: .reauthentication, makeChallenge: { original }, capture: {
            .init(perform: { _, _, _ in nil }, cancel: { cancellations += 1 }, feedbackIsCurrent: {
                model.cancel(ticketID: original.id); return true
            }, expectedAppleUserID: "original.apple")
        })
        XCTAssertNotNil(model.begin()); XCTAssertFalse(model.canPresent(ticketID: original.id))
        XCTAssertEqual(cancellations, 1); XCTAssertTrue(model.isWorking)
        model.providerCancelled(ticketID: original.id); XCTAssertFalse(model.isWorking)
    }

    func testPromptCancelBeforeNativeBeginReleasesWaitAndRejectsReusedAction() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow)
        XCTAssertTrue(flow.isReauthentication); XCTAssertFalse(flow.isWorking)
        f.prompt.cancel(action: action); await rejected { try await provider.value }
        XCTAssertTrue(f.providerFinished); XCTAssertEqual(f.cancelCalls, 1); XCTAssertNil(f.prompt.presentation)
        await rejected { try await f.request(action) }
    }
    func testPromptCancelAfterBeginRetainsProviderUntilActualCancellationCallback() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        f.prompt.cancel(action: action); await drainScheduling()
        XCTAssertNil(f.prompt.presentation); XCTAssertTrue(flow.isWorking); XCTAssertFalse(f.providerFinished); XCTAssertEqual(f.cancelCalls, 1)
        let next = try await f.action(); await rejected { try await f.request(next) }
        flow.providerCancelled(ticketID: original.id); await rejected { try await provider.value }
        XCTAssertTrue(f.providerFinished); XCTAssertFalse(flow.isWorking)
        let newProvider = await f.open(next); f.prompt.cancel(action: next); await rejected { try await newProvider.value }
    }
    func testDeniedLateProviderSuccessDrainsWithoutDeliveringCredential() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        f.prompt.cancel(action: action); XCTAssertFalse(f.providerFinished)
        await flow.complete(ticketID: original.id, response: response(original)); await rejected { try await provider.value }
        XCTAssertFalse(flow.isWorking); XCTAssertNil(flow.authenticatedSession); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testProviderTaskCancellationCannotReleaseAnAlreadyStartedNativeOperation() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        provider.cancel(); await drainScheduling()
        XCTAssertFalse(f.providerFinished); XCTAssertTrue(flow.isWorking)
        flow.fail(ticketID: original.id, error: Fault.rejected); await rejected { try await provider.value }
        XCTAssertFalse(flow.isWorking); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testDeliveredCredentialKeepsFlowBusyUntilActualHeldSDKOutcome() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        let callback = Task { await flow.complete(ticketID: original.id, response: self.response(original)) }
        let value = try await provider.value
        XCTAssertEqual(value.idToken, "local.identity.token"); XCTAssertEqual(value.rawNonce, original.rawNonce)
        XCTAssertTrue(flow.isWorking); XCTAssertNil(flow.authenticatedSession); XCTAssertNil(flow.errorMessage)
        f.prompt.complete(action: action); await callback.value
        XCTAssertFalse(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 0)
        f.prompt.cancel(action: action); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testExchangeCancellationRetainsOutcomeUntilActualHelperCompletion() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        var callbackFinished = false
        let callback = Task { await flow.complete(ticketID: original.id, response: self.response(original)); callbackFinished = true }
        _ = try await provider.value; f.prompt.cancel(action: action); await drainScheduling()
        XCTAssertFalse(callbackFinished); XCTAssertTrue(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 1)
        f.prompt.complete(action: action, error: CancellationError()); await callback.value
        XCTAssertTrue(callbackFinished); XCTAssertFalse(flow.isWorking); XCTAssertNil(flow.authenticatedSession)
    }
    func testAToBToAKeepsOriginalProviderOrSDKReservationUntilItsPhysicalReturn() async throws {
        for exchange in [false, true] {
            let f = Fixture(), action = try await f.action(), provider = await f.open(action)
            let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
            var callback: Task<Void, Never>?
            if exchange {
                callback = Task { await flow.complete(ticketID: original.id, response: self.response(original)) }
                _ = try await provider.value
            }
            f.roundTrip(); XCTAssertNil(f.prompt.presentation); XCTAssertTrue(flow.isWorking)
            if let callback { f.prompt.complete(action: action); await callback.value }
            else {
                XCTAssertFalse(f.providerFinished)
                await flow.complete(ticketID: original.id, response: response(original)); await rejected { try await provider.value }
            }
            XCTAssertFalse(flow.isWorking); XCTAssertNil(flow.authenticatedSession); XCTAssertEqual(f.cancelCalls, 1)
        }
    }
    func testWrongSubjectStateOrMissingTokenSettlesActualProviderWaitWithoutSDKCredential() async throws {
        for variant in 0..<3 {
            let f = Fixture(), action = try await f.action(), provider = await f.open(action)
            let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
            let reply = response(original, subject: variant == 0 ? "foreign.apple" : "original.apple",
                state: variant == 1 ? "foreign-state" : nil, token: variant == 2 ? nil : Data("local.identity.token".utf8))
            await flow.complete(ticketID: original.id, response: reply); await rejected { try await provider.value }
            XCTAssertFalse(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 0)
            // Existing deletion coordinator owns unavailable/canRetry feedback;
            // this provider presentation never retries the already-used action.
            XCTAssertNil(flow.authenticatedSession)
        }
    }
    func testRealProviderFailureSettlesOriginalWaitAndDoesNotNotifyUserCancellation() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        flow.fail(ticketID: original.id, error: Fault.rejected); await rejected { try await provider.value }
        XCTAssertFalse(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testUnpresentedBeginCancelledByFeedbackDoesNotLeavePhysicalProviderWait() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow)
        let observation = flow.objectWillChange.sink { if flow.isWorking { f.prompt.cancel(action: action) } }
        XCTAssertNil(flow.begin()); await rejected { try await provider.value }
        XCTAssertFalse(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 1)
        withExtendedLifetime(observation) {}
    }
    func testDeniedCaptureBeforeNativeBeginCannotLeaveAHiddenCredentialWait() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow)
        f.allowed = false; XCTAssertNil(flow.begin()); await rejected { try await provider.value }
        XCTAssertFalse(flow.isWorking); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testLateSuccessErrorAndDismissalCannotTouchNewActionPresentation() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let flow = try XCTUnwrap(f.prompt.presentation?.flow), original = try XCTUnwrap(flow.begin())
        let callback = Task { await flow.complete(ticketID: original.id, response: self.response(original)) }
        _ = try await provider.value; f.prompt.complete(action: action, error: Fault.rejected); await callback.value
        let next = try await f.action(), newProvider = await f.open(next)
        f.prompt.complete(action: action); f.prompt.cancel(action: action); flow.providerCancelled(ticketID: original.id)
        XCTAssertEqual(f.prompt.presentation?.action, next); XCTAssertEqual(f.cancelCalls, 0)
        f.prompt.cancel(action: next); await rejected { try await newProvider.value }
    }
    func testPromptRejectsMissingAppleSubjectBeforePresentation() async throws {
        let f = Fixture(), action = try await f.action()
        for subject in ["", "subject\nforeign", String(repeating: "a", count: 1025)] {
            await rejected { try await f.request(action, subject: subject) }; XCTAssertNil(f.prompt.presentation)
        }
        XCTAssertEqual(f.cancelCalls, 0)
    }
}
