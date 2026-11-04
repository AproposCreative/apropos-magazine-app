import AuthenticationServices
import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// The production UIViewRepresentable's actual Coordinator, with an injected
/// plain-object provider. No AS request/controller or Firebase is initialized.
@MainActor
final class AppleAuthorizationCoordinatorTests: XCTestCase {
    private typealias Coordinator = AppleAuthorizationButton.Coordinator
    private enum LocalError: Error { case unavailable }
    @MainActor private final class Handle {
        let identity = NSObject()
        let challenge: AppleSignInChallenge
        weak var coordinator: Coordinator?
        var starts = 0, cancellations = 0, releases = 0
        var onPerform: (() -> Void)?, onRelease: (() -> Void)?
        init(_ challenge: AppleSignInChallenge, _ coordinator: Coordinator) {
            self.challenge = challenge; self.coordinator = coordinator
        }
        func success(state: String? = nil, subject: String = "original-apple-subject") {
            coordinator?.receive(identity: identity, response: .init(identityToken: Data("local.identity.token".utf8),
                state: state ?? challenge.state, fullName: nil, userID: subject))
        }
        func fail(_ error: Error = LocalError.unavailable) { coordinator?.receive(identity: identity, error: error) }
    }
    @MainActor private final class Fixture {
        let purpose: AppleAccountFlowModel.Purpose
        let lifetime: AccountLoginLifetime?
        var captures = 0, returned = 0, failed = 0, cancelled = 0, exchanges = 0
        var capturedNonce: String?, capturedToken: String?
        var handles: [Handle] = []
        var coordinator: Coordinator?
        var current = true
        var factoryHook: ((Handle) -> Void)?
        var holdExchange = false
        var exchangeWait: CheckedContinuation<Void, Never>?
        var readyHook: (() -> Void)?
        var finishHook: (() -> Void)?
        lazy var callbacks = AppleLoginCallbacks(onFinished: { [unowned self] _ in finishHook?() })
        lazy var flow = AppleAccountFlowModel(purpose: purpose, makeChallenge: {
            .init(id: UUID(), rawNonce: "original-raw-nonce", state: UUID().uuidString)
        }, capture: { [unowned self] in
            captures += 1
            if purpose == .login { callbacks.started(UUID()) }
            return .init(perform: { [unowned self] token, nonce, _ in
                exchanges += 1; capturedNonce = nonce; capturedToken = token
                if holdExchange { await withCheckedContinuation { exchangeWait = $0 } }
                return purpose == .login ? ReaderAccountSession(uid: "reader-A", email: "local@example.invalid", isEmailVerified: true) : nil
            }, providerReturned: { [unowned self] in returned += 1 },
                providerFailed: { [unowned self] in failed += 1; return current },
                cancel: { [unowned self] in cancelled += 1 }, feedbackIsCurrent: { [unowned self] in current },
                expectedAppleUserID: purpose == .reauthentication ? "original-apple-subject" : nil)
        })
        init(purpose: AppleAccountFlowModel.Purpose = .reauthentication, lifetime: AccountLoginLifetime? = nil) {
            self.purpose = purpose; self.lifetime = lifetime
        }
        func make() -> Coordinator {
            let value = Coordinator(flow: flow, callbacks: callbacks, lifetime: lifetime,
                providerFactory: { [unowned self] challenge, owner in
                    let handle = Handle(challenge, owner); handles.append(handle); factoryHook?(handle)
                    return .init(identity: handle.identity, perform: { handle.starts += 1; handle.onPerform?() },
                        cancel: { handle.cancellations += 1 }, release: { handle.releases += 1; handle.onRelease?() })
                }, presentationReady: { [unowned self] in readyHook?(); return true })
            coordinator = value; return value
        }
        func releaseExchange() { let old = exchangeWait; exchangeWait = nil; old?.resume() }
        func drain() { handles.forEach { $0.fail() }; releaseExchange() }
    }
    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 { if condition() { return }; await Task.yield() }
        XCTFail("Expected original local callback did not settle", file: file, line: line)
    }

    func testActualCoordinatorStartsOneOriginalNonceAndStateUntilCallback() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make()
        coordinator.signIn(); coordinator.signIn()
        XCTAssertEqual(f.captures, 1); XCTAssertEqual(f.handles.count, 1); XCTAssertEqual(f.handles[0].starts, 1)
        XCTAssertTrue(f.flow.isWorking); XCTAssertNotEqual(f.handles[0].challenge.hashedNonce, f.handles[0].challenge.rawNonce)
        f.handles[0].success(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.returned, 1); XCTAssertEqual(f.exchanges, 1)
        XCTAssertEqual(f.capturedNonce, "original-raw-nonce"); XCTAssertEqual(f.capturedToken, "local.identity.token")
        XCTAssertEqual(f.handles[0].releases, 1); XCTAssertNil(f.flow.authenticatedSession); XCTAssertNil(f.flow.errorMessage)
    }

    func testWrongControllerIdentityCannotConsumeOriginalProviderRequest() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make(); coordinator.signIn()
        coordinator.receive(identity: NSObject(), response: .init(identityToken: Data("foreign".utf8), state: f.handles[0].challenge.state, fullName: nil, userID: "original-apple-subject"))
        coordinator.receive(identity: NSObject(), error: LocalError.unavailable)
        XCTAssertTrue(f.flow.isWorking); XCTAssertEqual(f.returned, 0); XCTAssertEqual(f.failed, 0)
        XCTAssertEqual(f.handles[0].releases, 0)
        f.handles[0].success(); await eventually { !f.flow.isWorking }; XCTAssertEqual(f.exchanges, 1)
    }

    func testDuplicateCallbacksAreReservedSynchronouslyBeforeMainActorExchange() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make(); f.holdExchange = true
        coordinator.signIn(); let handle = f.handles[0]
        handle.success(); handle.success(); handle.fail()
        XCTAssertEqual(handle.releases, 1)
        await eventually { f.exchangeWait != nil }
        XCTAssertEqual(f.returned, 1); XCTAssertEqual(f.exchanges, 1); XCTAssertEqual(f.failed, 0)
        coordinator.signIn(); XCTAssertEqual(f.handles.count, 1)
        f.releaseExchange(); await eventually { !f.flow.isWorking }
    }

    func testSynchronousPerformCallbackUsesTheSameConcreteControllerAndTicket() async {
        let f = Fixture(); defer { f.drain() }
        f.factoryHook = { handle in handle.onPerform = { [weak handle] in handle?.success(); handle?.fail() } }
        f.make().signIn(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.handles.count, 1); XCTAssertEqual(f.handles[0].starts, 1); XCTAssertEqual(f.handles[0].releases, 1)
        XCTAssertEqual(f.exchanges, 1); XCTAssertEqual(f.returned, 1); XCTAssertEqual(f.failed, 0)
    }

    func testStateMismatchNeverReachesExchangeAndNewTapGetsNewChallenge() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make(); coordinator.signIn()
        let original = f.handles[0]; original.success(state: "different-state")
        await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 0); XCTAssertNotNil(f.flow.errorMessage)
        coordinator.signIn(); XCTAssertEqual(f.handles.count, 2)
        XCTAssertNotEqual(original.challenge.id, f.handles[1].challenge.id); XCTAssertNotEqual(original.challenge.state, f.handles[1].challenge.state)
        original.success(); XCTAssertTrue(f.flow.isWorking)
        f.handles[1].success(); await eventually { !f.flow.isWorking }; XCTAssertEqual(f.exchanges, 1)
    }

    func testDifferentAppleSubjectCannotBeReauthenticatedAsCurrentReader() async {
        let f = Fixture(); defer { f.drain() }; f.make().signIn(); f.handles[0].success(subject: "other-apple-subject")
        await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 0); XCTAssertNil(f.flow.authenticatedSession); XCTAssertNotNil(f.flow.errorMessage)
        XCTAssertFalse(f.flow.errorMessage?.localizedCaseInsensitiveContains("login") ?? true)
    }

    func testReauthenticationDetachCancelsDespiteValidLoginLifetimeAndWaitsForActualCallback() async {
        let f = Fixture(lifetime: AccountLoginLifetime()); defer { f.drain() }; let coordinator = f.make()
        coordinator.signIn(); coordinator.viewDetached(); coordinator.cancelPresentation()
        XCTAssertFalse(f.lifetime!.isInvalidated); XCTAssertTrue(f.flow.isWorking)
        XCTAssertEqual(f.handles[0].cancellations, 1); XCTAssertEqual(f.handles[0].releases, 0)
        coordinator.signIn(); XCTAssertEqual(f.handles.count, 1)
        f.handles[0].success(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 0); XCTAssertEqual(f.returned, 1); XCTAssertNil(f.flow.errorMessage)
    }

    func testLoginDetachWithValidLifetimeKeepsExistingSuccessfulExchangeBehavior() async {
        let f = Fixture(purpose: .login, lifetime: AccountLoginLifetime()); defer { f.drain() }; let coordinator = f.make()
        coordinator.signIn(); coordinator.viewDetached()
        XCTAssertEqual(f.handles[0].cancellations, 0); XCTAssertEqual(f.cancelled, 0)
        f.handles[0].success(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 1); XCTAssertEqual(f.flow.authenticatedSession?.uid, "reader-A")
    }

    func testLifetimeInvalidationWaitsForActualCancellationCallbackBeforeRetiringRequest() async {
        let lifetime = AccountLoginLifetime(), f = Fixture(lifetime: lifetime); defer { f.drain() }
        f.make().signIn(); lifetime.invalidate()
        XCTAssertTrue(f.flow.isWorking); XCTAssertEqual(f.handles[0].cancellations, 1)
        f.handles[0].fail(NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.canceled.rawValue))
        await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 0); XCTAssertNil(f.flow.errorMessage); XCTAssertEqual(f.handles[0].releases, 1)
    }

    func testBeginPublicationDetachCannotCreateAnUnpresentableController() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make(); var armed = true
        let observer = f.flow.objectWillChange.sink { if armed { armed = false; coordinator.viewDetached() } }
        coordinator.signIn()
        XCTAssertFalse(armed); XCTAssertEqual(f.captures, 1); XCTAssertTrue(f.handles.isEmpty)
        XCTAssertFalse(f.flow.isWorking); XCTAssertEqual(f.failed, 1)
        withExtendedLifetime(observer) {}
    }

    func testFactoryReentryDetachReleasesUnstartedHandleWithoutPerforming() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make()
        f.factoryHook = { _ in coordinator.viewDetached() }
        coordinator.signIn()
        XCTAssertEqual(f.handles.count, 1); XCTAssertEqual(f.handles[0].starts, 0)
        XCTAssertEqual(f.handles[0].releases, 1); XCTAssertFalse(f.flow.isWorking); XCTAssertEqual(f.exchanges, 0)
    }

    func testReleaseHookDuplicateCannotReplaceFirstAcceptedCallback() async {
        let f = Fixture(); defer { f.drain() }; f.make().signIn(); let original = f.handles[0]
        original.onRelease = { [weak original] in original?.fail(); original?.success(state: "wrong") }
        original.success(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(original.releases, 1); XCTAssertEqual(f.exchanges, 1); XCTAssertEqual(f.returned, 1); XCTAssertEqual(f.failed, 0)
    }

    func testFactoryRevokesOriginalFlowWithoutDetachingAndCannotPerformOldProvider() async {
        for cancelDirectly in [true, false] {
            let f = Fixture(); defer { f.drain() }; let coordinator = f.make()
            f.factoryHook = { handle in
                if cancelDirectly { f.flow.cancel(ticketID: handle.challenge.id) }
                else { f.current = false }
            }
            coordinator.signIn()
            XCTAssertEqual(f.handles.count, 1); XCTAssertEqual(f.handles[0].starts, 0)
            XCTAssertEqual(f.handles[0].releases, 1); XCTAssertFalse(f.flow.isWorking)
            XCTAssertEqual(f.exchanges, 0); XCTAssertEqual(f.returned, 0)
        }
    }

    func testReauthActivationMainHopRejectsStaleOwnershipWithoutSharedAuthLookup() async {
        let f = Fixture(); defer { f.drain() }; let coordinator = f.make(); var current = true
        coordinator.activate(UUID(), isCurrent: { current }); current = false
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(f.captures, 0); XCTAssertTrue(f.handles.isEmpty); XCTAssertNil(FirebaseApp.allApps)
        current = true; let activation = UUID()
        coordinator.activate(activation, isCurrent: { current }); coordinator.activate(activation, isCurrent: { current })
        await eventually { f.handles.count == 1 }
        XCTAssertEqual(f.captures, 1); f.handles[0].success(); await eventually { !f.flow.isWorking }
    }

    func testDetachedReauthIsRetainedOnlyUntilPhysicalProviderAndExchangeRetire() async {
        let f = Fixture(); defer { f.drain() }
        weak var weakCoordinator: Coordinator?
        do { let coordinator = f.make(); weakCoordinator = coordinator; coordinator.signIn(); coordinator.viewDetached() }
        f.coordinator = nil
        XCTAssertNotNil(weakCoordinator); XCTAssertTrue(f.flow.isWorking)
        f.handles[0].success(); await eventually { !f.flow.isWorking && weakCoordinator == nil }
        XCTAssertEqual(f.exchanges, 0); XCTAssertEqual(f.handles[0].releases, 1)
    }

    func testLoginFinishReentryCannotClearTheNewPhysicalRequest() async {
        let f = Fixture(purpose: .login); defer { f.drain() }; let coordinator = f.make()
        f.finishHook = { [weak coordinator] in f.finishHook = nil; coordinator?.signIn() }
        coordinator.signIn(); f.handles[0].success()
        await eventually { f.handles.count == 2 }
        XCTAssertTrue(f.flow.isWorking); XCTAssertEqual(f.handles[1].starts, 1)
        f.handles[0].fail(); XCTAssertTrue(f.flow.isWorking)
        f.handles[1].success(); await eventually { !f.flow.isWorking }
        XCTAssertEqual(f.exchanges, 2); XCTAssertEqual(f.handles[1].releases, 1)
    }
}
