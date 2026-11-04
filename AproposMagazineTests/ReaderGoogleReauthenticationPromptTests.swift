import Combine
import FirebaseCore
import GoogleSignIn
import XCTest
@testable import Apropos

@MainActor
final class ReaderGoogleReauthenticationPromptTests: XCTestCase {
    private typealias Prompt = ReaderGoogleReauthenticationPrompt
    private typealias Coordinator = ReaderAccountDeletionCoordinator
    private typealias Identity = GoogleSignInService.ReauthenticationIdentity
    private typealias Callback = @Sendable (Identity?, Error?) -> Void
    private enum Fault: Error { case rejected }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var allowed = true, cancelCalls = 0, providerCalls = 0
        var finished = false
        var currentHook: (@MainActor () -> Void)?
        var providerHook: GoogleSignInService.ReauthenticationProvider?
        var callbacks: [Callback] = []
        var admissions: [@MainActor () -> Bool] = []
        var entered: XCTestExpectation?
        lazy var service = GoogleSignInService(reauthenticationProvider: { [unowned self] admitted, completion in
            self.providerCalls += 1; self.admissions.append(admitted); self.callbacks.append(completion)
            let entered = self.entered; self.entered = nil; entered?.fulfill()
            if let hook = self.providerHook { try hook(admitted, completion) }
        })
        lazy var prompt = Prompt(canonical: canonical, service: service)
        var identity: Identity { .init(idToken: "local.id.token", accessToken: "local.access.token", userID: "original.google") }
        init() { _ = canonical.adopt(.init(uid: "reader_a", email: "fixture@example.invalid", isEmailVerified: false)) }
        func action() async throws -> Coordinator.ActionTicket {
            var captured: Coordinator.ActionTicket?
            let done = XCTestExpectation(description: "Actual original coordinator action")
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
        func current(_ action: Coordinator.ActionTicket) -> Bool {
            currentHook?(); return allowed && canonical.isCurrent(action.context)
        }
        func runService(_ action: Coordinator.ActionTicket) async throws -> Identity {
            try await service.reauthenticate(action: action, expectedGoogleUserID: "original.google", isCurrent: { self.current(action) })
        }
        func startService(_ action: Coordinator.ActionTicket) async -> Task<Identity, Error> {
            let started = XCTestExpectation(description: "Original physical provider started"); entered = started; finished = false
            let task = Task { defer { self.finished = true }; return try await self.runService(action) }
            let result = await XCTWaiter.fulfillment(of: [started], timeout: 3); XCTAssertEqual(result, .completed)
            return task
        }
        func request(_ action: Coordinator.ActionTicket, subject: String = "original.google") async throws -> Prompt.CredentialValue {
            try await prompt.request(action: action, expectedGoogleUserID: subject, isCurrent: { self.current(action) },
                onCancel: { self.cancelCalls += 1 })
        }
        func open(_ action: Coordinator.ActionTicket) async -> Task<Prompt.CredentialValue, Error> {
            let shown = XCTestExpectation(description: "Original Google prompt"); var observed = false
            let observation = prompt.objectWillChange.sink { [unowned self] in
                if !observed, self.prompt.presentation?.action == action { observed = true; shown.fulfill() }
            }
            finished = false
            let task = Task { defer { self.finished = true }; return try await self.request(action) }
            let result = await XCTWaiter.fulfillment(of: [shown], timeout: 3); XCTAssertEqual(result, .completed)
            withExtendedLifetime(observation) {}; return task
        }
        func startPrompt(_ action: Coordinator.ActionTicket) async -> Task<Void, Never> {
            let started = XCTestExpectation(description: "Prompt's physical Google provider started"); entered = started
            let task = Task { await self.prompt.start(action: action) }
            let result = await XCTWaiter.fulfillment(of: [started], timeout: 3); XCTAssertEqual(result, .completed)
            return task
        }
        func roundTrip() {
            _ = canonical.adopt(.init(uid: "reader_b", email: "other@example.invalid", isEmailVerified: false))
            _ = canonical.adopt(.init(uid: "reader_a", email: "fixture@example.invalid", isEmailVerified: false))
        }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func rejected<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected original operation rejection", file: file, line: line) } catch {}
    }
    private func cancelled<T>(_ operation: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected original cancellation", file: file, line: line) }
        catch is CancellationError {} catch { XCTFail("Unexpected non-cancellation failure", file: file, line: line) }
    }
    private func drainScheduling() async { for _ in 0..<6 { await Task.yield() } }

    func testInjectedServiceAndPromptConstructionAreInert() {
        let f = Fixture(); _ = f.prompt
        XCTAssertEqual(f.providerCalls, 0); XCTAssertFalse(f.service.isReauthenticating)
        XCTAssertFalse(f.service.isSignedIn); XCTAssertNil(f.service.user); XCTAssertNil(f.prompt.presentation)
    }
    func testActualServiceReturnsOriginalCredentialWithoutChangingLoginStateOrFeedback() async throws {
        let f = Fixture(), action = try await f.action()
        f.service.isSignedIn = true; f.service.errorMessage = "existing-login-feedback"; f.service.showErrorDialog = true
        let task = await f.startService(action)
        XCTAssertTrue(f.service.isReauthenticating); XCTAssertTrue(f.admissions[0]())
        f.callbacks[0](f.identity, nil); let result = try await task.value
        XCTAssertEqual(result, f.identity); XCTAssertFalse(f.service.isReauthenticating)
        XCTAssertTrue(f.service.isSignedIn); XCTAssertNil(f.service.user)
        XCTAssertEqual(f.service.errorMessage, "existing-login-feedback"); XCTAssertTrue(f.service.showErrorDialog)
    }
    func testActualServiceRejectsWrongSubjectMissingResultAndMalformedCredential() async throws {
        let values: [Identity?] = [nil,
            .init(idToken: "id", accessToken: "access", userID: "foreign.google"),
            .init(idToken: "", accessToken: "access", userID: "original.google"),
            .init(idToken: "id", accessToken: "", userID: "original.google"),
            .init(idToken: "id\nforeign", accessToken: "access", userID: "original.google"),
            .init(idToken: "id", accessToken: "with spaces", userID: "original.google"),
            .init(idToken: String(repeating: "a", count: 16_385), accessToken: "access", userID: "original.google")]
        for value in values {
            let f = Fixture(), action = try await f.action(), task = await f.startService(action)
            f.callbacks[0](value, nil); await rejected { try await task.value }
            XCTAssertFalse(f.service.isReauthenticating); XCTAssertNil(f.service.user); XCTAssertFalse(f.service.isSignedIn)
        }
    }
    func testFirstPhysicalErrorWinsResultAndSecondSuccessBeforeMainActorHop() async throws {
        let f = Fixture(), action = try await f.action(), task = await f.startService(action)
        f.callbacks[0](f.identity, Fault.rejected); f.callbacks[0](f.identity, nil)
        do { _ = try await task.value; XCTFail("Error must win") }
        catch let error as Fault { XCTAssertEqual(String(describing: error), "rejected") }
        catch { XCTFail("Unexpected error type") }
        XCTAssertFalse(f.service.isReauthenticating)
    }
    func testFirstPhysicalSuccessCannotBeReplacedBySecondErrorBeforeMainActorHop() async throws {
        let f = Fixture(), action = try await f.action(), task = await f.startService(action)
        f.callbacks[0](f.identity, nil); f.callbacks[0](nil, Fault.rejected)
        let result = try await task.value; XCTAssertEqual(result, f.identity)
    }
    func testActualSDKCancellationErrorUsesCancellationSemantics() async throws {
        let f = Fixture(), action = try await f.action(), task = await f.startService(action)
        f.callbacks[0](nil, NSError(domain: kGIDSignInErrorDomain, code: -5))
        await cancelled { try await task.value }; XCTAssertFalse(f.service.isReauthenticating)
    }
    func testServiceCancellationRetainsPhysicalSlotAndRefusesOverlapUntilCallback() async throws {
        let f = Fixture(), action = try await f.action(), task = await f.startService(action)
        task.cancel(); await drainScheduling()
        XCTAssertTrue(f.service.isReauthenticating); XCTAssertFalse(f.finished)
        let next = try await f.action(); await rejected { try await f.runService(next) }; XCTAssertEqual(f.providerCalls, 1)
        f.callbacks[0](f.identity, nil); await cancelled { try await task.value }
        XCTAssertFalse(f.service.isReauthenticating); XCTAssertTrue(f.finished)
    }
    func testOriginalGenerationAndObservedDenialCannotReviveBeforeCallback() async throws {
        for roundTrip in [true, false] {
            let f = Fixture(), action = try await f.action(), task = await f.startService(action)
            if roundTrip { f.roundTrip() }
            else { f.allowed = false; XCTAssertFalse(f.admissions[0]()); f.allowed = true; XCTAssertFalse(f.admissions[0]()) }
            f.callbacks[0](f.identity, nil); await cancelled { try await task.value }
            XCTAssertFalse(f.service.isReauthenticating)
        }
    }
    func testLateOldDuplicateCallbackCannotFinishNewPhysicalFlight() async throws {
        let f = Fixture(), first = try await f.action(), old = await f.startService(first)
        f.callbacks[0](f.identity, nil); _ = try await old.value
        let second = try await f.action(), newer = await f.startService(second)
        f.callbacks[0](nil, Fault.rejected); f.service.cancelReauthentication(action: first); await drainScheduling()
        XCTAssertTrue(f.service.isReauthenticating); XCTAssertFalse(f.finished)
        f.callbacks[1](f.identity, nil); let result = try await newer.value; XCTAssertEqual(result, f.identity)
    }
    func testOwnershipHookReentryAndCancelledEntryCreateNoProvider() async throws {
        let f = Fixture(), action = try await f.action()
        f.currentHook = { f.service.cancelReauthentication(action: action) }
        await cancelled { try await f.runService(action) }; XCTAssertEqual(f.providerCalls, 0); XCTAssertFalse(f.service.isReauthenticating)
        f.currentHook = nil
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await f.runService(action) }
        await cancelled { try await task.value }; XCTAssertEqual(f.providerCalls, 0)
    }
    func testProviderSetupThrowSettlesWithoutSDKAndFirstSynchronousCallbackStillWins() async throws {
        let failure = Fixture(), action = try await failure.action()
        failure.providerHook = { _, _ in throw Fault.rejected }
        await rejected { try await failure.runService(action) }; XCTAssertFalse(failure.service.isReauthenticating)
        let first = Fixture(), firstAction = try await first.action()
        first.providerHook = { _, callback in callback(first.identity, nil); throw Fault.rejected }
        let result = try await first.runService(firstAction); XCTAssertEqual(result, first.identity)
    }
    func testInjectedLastPresenterFactoryGuardPreventsPhysicalStartAfterDenial() async throws {
        let f = Fixture(), action = try await f.action(); var physicalStarts = 0
        f.providerHook = { admitted, callback in
            XCTAssertTrue(admitted()); f.allowed = false // Models a presenter/factory hook replacing the original owner.
            guard admitted() else { callback(nil, CancellationError()); return }
            physicalStarts += 1; callback(f.identity, nil)
        }
        await cancelled { try await f.runService(action) }; XCTAssertEqual(physicalStarts, 0); XCTAssertFalse(f.service.isReauthenticating)
    }

    func testPromptCancelBeforeButtonStartHasNoProviderEffects() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        XCTAssertEqual(f.prompt.presentation?.isWorking, false); f.prompt.cancel(action: action)
        await cancelled { try await provider.value }; await f.prompt.start(action: action)
        XCTAssertEqual(f.providerCalls, 0); XCTAssertEqual(f.cancelCalls, 1); XCTAssertNil(f.prompt.presentation)
    }
    func testPromptCancelWhileProviderOpenWaitsForPhysicalReplyBeforeFinishingHelper() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action), starting = await f.startPrompt(action)
        XCTAssertEqual(f.prompt.presentation?.isWorking, true)
        f.prompt.cancel(action: action); await drainScheduling()
        XCTAssertNil(f.prompt.presentation); XCTAssertFalse(f.finished); XCTAssertTrue(f.service.isReauthenticating)
        f.callbacks[0](f.identity, nil); await starting.value; await cancelled { try await provider.value }
        XCTAssertTrue(f.finished); XCTAssertFalse(f.service.isReauthenticating); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testPromptCredentialDeliveryKeepsBusyUntilActualSDKCompletion() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action), starting = await f.startPrompt(action)
        f.callbacks[0](f.identity, nil); let value = try await provider.value
        XCTAssertEqual(value.idToken, f.identity.idToken); XCTAssertEqual(value.accessToken, f.identity.accessToken)
        XCTAssertFalse(f.service.isReauthenticating); XCTAssertEqual(f.prompt.presentation?.isWorking, true)
        f.prompt.complete(action: action); await starting.value
        XCTAssertNil(f.prompt.presentation); XCTAssertFalse(f.service.isSignedIn); XCTAssertNil(f.service.user)
        f.prompt.cancel(action: action); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testPromptCancellationDuringSDKDoesNotReleaseOutcomeBeforeActualCompletion() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        var startFinished = false
        let started = XCTestExpectation(description: "Provider starts"); f.entered = started
        let starting = Task { await f.prompt.start(action: action); startFinished = true }
        let result = await XCTWaiter.fulfillment(of: [started], timeout: 3); XCTAssertEqual(result, .completed)
        f.callbacks[0](f.identity, nil); _ = try await provider.value
        f.prompt.cancel(action: action); await drainScheduling(); XCTAssertFalse(startFinished); XCTAssertNil(f.prompt.presentation)
        f.prompt.complete(action: action, error: CancellationError()); await starting.value
        XCTAssertTrue(startFinished); XCTAssertEqual(f.cancelCalls, 1)
    }
    func testPromptWrongProviderSubjectCannotReachHeldSDKCredentialWait() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action), starting = await f.startPrompt(action)
        f.callbacks[0](.init(idToken: "id", accessToken: "access", userID: "foreign.google"), nil)
        await starting.value; await rejected { try await provider.value }
        XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 0)
    }
    func testPromptAToBToAPreservesPhysicalProviderAndSDKWaitOwnership() async throws {
        for exchange in [false, true] {
            let f = Fixture(), action = try await f.action(), provider = await f.open(action), starting = await f.startPrompt(action)
            if exchange { f.callbacks[0](f.identity, nil); _ = try await provider.value }
            f.roundTrip(); XCTAssertNil(f.prompt.presentation)
            if exchange { f.prompt.complete(action: action) }
            else { XCTAssertFalse(f.finished); XCTAssertTrue(f.service.isReauthenticating); f.callbacks[0](f.identity, nil) }
            await starting.value
            if !exchange { await cancelled { try await provider.value } }
            XCTAssertEqual(f.cancelCalls, 1); XCTAssertFalse(f.service.isSignedIn)
        }
    }
    func testRepeatedButtonTasksAndCancelledProviderWaitCannotStartSecondGoogleFlow() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action), starting = await f.startPrompt(action)
        await f.prompt.start(action: action); XCTAssertEqual(f.providerCalls, 1)
        provider.cancel(); await drainScheduling(); XCTAssertFalse(f.finished); XCTAssertTrue(f.service.isReauthenticating)
        f.callbacks[0](f.identity, nil); await starting.value; await cancelled { try await provider.value }
        XCTAssertEqual(f.cancelCalls, 1)
    }
    func testReentrantCancelDuringBusyPublicationPreventsProviderConstruction() async throws {
        let f = Fixture(), action = try await f.action(), provider = await f.open(action)
        let observation = f.prompt.objectWillChange.sink {
            if f.prompt.presentation?.isWorking == true { f.prompt.cancel(action: action) }
        }
        await f.prompt.start(action: action); await cancelled { try await provider.value }
        XCTAssertEqual(f.providerCalls, 0); XCTAssertNil(f.prompt.presentation); XCTAssertEqual(f.cancelCalls, 1)
        withExtendedLifetime(observation) {}
    }
    func testLateOldCompletionAndDismissalCannotCancelNewAction() async throws {
        let f = Fixture(), oldAction = try await f.action(), oldProvider = await f.open(oldAction), oldStart = await f.startPrompt(oldAction)
        f.callbacks[0](f.identity, nil); _ = try await oldProvider.value
        f.prompt.complete(action: oldAction, error: Fault.rejected); await oldStart.value
        let next = try await f.action(), nextProvider = await f.open(next)
        f.prompt.complete(action: oldAction); f.prompt.cancel(action: oldAction); await f.prompt.start(action: oldAction)
        XCTAssertEqual(f.prompt.presentation?.action, next); XCTAssertEqual(f.providerCalls, 1); XCTAssertEqual(f.cancelCalls, 0)
        f.prompt.cancel(action: next); await cancelled { try await nextProvider.value }
    }
    func testPromptRejectsMissingOrMalformedOriginalSubjectWithoutPresentation() async throws {
        let f = Fixture(), action = try await f.action()
        for subject in ["", "subject\nforeign", String(repeating: "a", count: 1025)] {
            await rejected { try await f.request(action, subject: subject) }; XCTAssertNil(f.prompt.presentation)
        }
        XCTAssertEqual(f.providerCalls, 0)
    }
}
