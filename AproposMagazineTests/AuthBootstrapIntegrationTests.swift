import Combine
import FirebaseCore
import XCTest
@testable import Apropos

/// Actual Auth/AppDelegate entry points and actual guarded startup, with only local effects.
@MainActor
final class AuthBootstrapIntegrationTests: XCTestCase {
    private typealias Startup = ReaderStartupCoordinator
    private typealias Contract = ReaderAuthoritativeReadContract
    private enum Injected: Error { case rejected }

    @MainActor private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Error>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation; entered.fulfill()
            }
        }
        func release() {
            guard let continuation else { XCTFail("Expected physical wait"); return }
            self.continuation = nil; continuation.resume()
        }
    }
    @MainActor private final class Pending {
        let done: XCTestExpectation
        var task: Task<Void, Never>?
        var result: Result<Startup.Receipt, Error>?
        init(_ done: XCTestExpectation) { self.done = done }
    }
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
    }
    @MainActor private final class Fixture {
        let sdk: ReaderSDKStartupState
        let auth: AuthService
        lazy var delegate = AppDelegate(startup: sdk, identity: auth.bootstrapIdentity, actualUserID: { [unowned self] in
            self.uidHook?(); return self.actualUID
        })
        let configuration: Startup.Configuration
        var actualUID: String?
        var events: [String] = []
        var publications = 0
        var effects: [String: Int] = [:]
        var starts = 0
        var uidHook: (() -> Void)?
        var revokeHook: ((@escaping () -> Bool) -> Bool)?
        var publishHook: (() -> Void)?
        var usePublicationBridge = false
        var profileRevocationHook: (() -> Void)?
        private let publicationBridge = CanonicalAccountPublication()
        var markerGate: Gate?
        var beforeAdmissionGate: Gate?
        var afterAdmissionGate: Gate?
        var verifierFails = false
        var starterFails = false
        var missingMembership = false
        var deadlines: [@MainActor () -> Void] = []
        lazy var coordinator: Startup = makeCoordinator()

        init(legacy: Bool = false) throws {
            sdk = legacy ? .application : ReaderSDKStartupState()
            auth = AuthService(startup: sdk)
            configuration = try Startup.Configuration(projectID: "local-fixture", appID: "local-app",
                installationID: UUID(), writerFenceRevision: String(repeating: "a", count: 64),
                migrationRevision: String(repeating: "b", count: 64))
        }
        var context: CanonicalSessionState.ContextTicket { auth.bootstrapIdentity.contextTicket() }
        func session(_ uid: String) -> ReaderAccountSession {
            .init(uid: uid, email: "fixture@example.invalid", isEmailVerified: true)
        }
        @discardableResult
        func observe(_ uid: String?, updateActual: Bool = true) -> CanonicalSessionState.ContextTicket? {
            if updateActual { actualUID = uid }
            let original = uid.map(session)
            return auth.observeIdentity(original, currentUserID: { [unowned self] in
                self.uidHook?(); return self.actualUID
            }, revokeReader: { [unowned self] stillCurrent in
                self.events.append("revoke")
                if let hook = self.revokeHook { return hook(stillCurrent) }
                return self.auth.state.suspend(stillPermitted: stillCurrent) != nil
            }, publishReader: { [unowned self] originalGuard in
                self.publications += 1; self.events.append("publish:" + (uid ?? "guest"))
                if self.usePublicationBridge {
                    var result: CanonicalSessionState.ContextTicket?
                    let completed = self.publicationBridge.performReaderTransition(expectedUserID: uid,
                        currentUserID: { self.actualUID }, revokeProfile: {
                            self.effects["profileRevocation", default: 0] += 1
                            self.profileRevocationHook?()
                            return true
                        }, revokePreferences: {
                            self.effects["preferencesRevocation", default: 0] += 1; return true
                        }, revocationsCurrent: { true }, dependentSteps: self.readerSteps(), commitCanonical: {
                            result = self.auth.state.adopt(original, stillPermitted: originalGuard)
                            return result != nil
                        }, startLoads: { self.effects["loads", default: 0] += 1 }, permission: originalGuard)
                    return completed ? result : nil
                }
                let result = self.auth.state.adopt(original, stillPermitted: originalGuard)
                self.publishHook?()
                return result
            })
        }
        func readerSteps() -> [() -> Void] {
            ["reference", "profile", "favorites", "preferences", "FCM"].map { name in
                { [unowned self] in self.effects[name, default: 0] += 1; self.events.append(name) }
            }
        }
        private func makeCoordinator() -> Startup {
            let marker: @MainActor () async throws -> Startup.Marker? = { [unowned self] in
                self.events.append("marker")
                if let gate = self.markerGate { self.markerGate = nil; try await gate.wait() }
                return nil
            }
            let membership: @MainActor (Contract.MembershipRequest) async throws -> Contract.MembershipSnapshot = { [unowned self] request in
                self.events.append("membership")
                let echoed = try JSONSerialization.jsonObject(with: Contract.encode(request))
                let value: Any
                if self.missingMembership { value = NSNull() }
                else { value = ["schemaVersion": 1, "ownerUID": request.expectedUID, "epoch": 7, "state": "active"] as [String: Any] }
                return try Contract.decodeMembershipResponse(data: JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "scope": Contract.membershipScope, "request": echoed,
                    "membership": value, "validUntilMs": 20_000
                ]), for: request)
            }
            let verifier: Startup.Verifier = { [unowned self] challenge in
                self.events.append("verify")
                if self.verifierFails { throw Injected.rejected }
                return .init(challenge: challenge, coverage: .allPersistedWritersIncludingPreviousAccounts,
                    writerFenceRevision: self.configuration.writerFenceRevision,
                    migrationRevision: self.configuration.migrationRevision, validUntilMs: 20_000)
            }
            let starter: @MainActor (Startup.Receipt, @escaping Startup.StartAdmission) async throws -> Void = { [unowned self] _, admit in
                if let gate = self.beforeAdmissionGate { try await gate.wait() }
                try admit() // The production coordinator's exact last admission; no fake state mutation.
                self.starts += 1; self.events.append("start")
                if let gate = self.afterAdmissionGate { try await gate.wait() }
                if self.starterFails { throw Injected.rejected }
            }
            return Startup(canonical: auth.bootstrapIdentity, sdkState: sdk, configuration: configuration,
                readMarker: marker, readMembership: membership, verify: verifier, startSDK: starter,
                now: { 10_000 }, schedule: { [unowned self] callback in self.deadlines.append(callback); return {} })
        }
    }

    override func setUp() { super.setUp(); XCTAssertNil(FirebaseApp.allApps) }
    override func tearDown() { XCTAssertNil(FirebaseApp.allApps); super.tearDown() }

    private func launch(_ f: Fixture) -> Pending {
        let pending = Pending(expectation(description: "Startup caller finished")), original = f.context
        pending.task = Task { @MainActor in
            do { pending.result = .success(try await f.coordinator.start(context: original)) }
            catch { pending.result = .failure(error) }
            pending.done.fulfill()
        }
        return pending
    }
    private func expectFailure(_ pending: Pending, _ failure: Startup.Failure? = nil) async {
        await fulfillment(of: [pending.done], timeout: 3)
        guard case .failure(let error) = pending.result else { return XCTFail("Expected rejected startup") }
        if let failure { XCTAssertEqual(error as? Startup.Failure, failure) }
    }
    private func waitIdle(_ coordinator: Startup) async {
        let flag = Flag()
        let predicate = NSPredicate { _, _ in
            Task { @MainActor in flag.set(!coordinator.isBusy) }
            return flag.value
        }
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3)
        XCTAssertFalse(coordinator.isBusy)
    }
    private func open(_ f: Fixture) async throws -> Startup.Receipt {
        try await f.coordinator.start(context: f.context)
    }

    func testGuardedConstructionAndRestoringStateDoNotConstructReaderEffects() throws {
        let f = try Fixture(); _ = f.coordinator
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .unresolved)
        f.delegate.runAccountStartup(authOnly: { f.events.append("auth") }, readerSteps: f.readerSteps(),
                                    observeAuth: { f.events.append("observe") })
        XCTAssertEqual(f.events, ["auth", "observe"])
        XCTAssertTrue(f.effects.isEmpty); XCTAssertEqual(f.publications, 0); XCTAssertEqual(f.starts, 0)
    }

    func testConfirmedGuestRemainsAuthOnlyInGuardedMode() async throws {
        let f = try Fixture()
        XCTAssertNil(f.observe(nil))
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .guest)
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
        let pending = launch(f); await expectFailure(pending, .unavailable)
        XCTAssertEqual(f.publications, 0); XCTAssertEqual(f.starts, 0); XCTAssertTrue(f.effects.isEmpty)
    }

    func testRestoredAccountDoesNotPublishProfileFavoritesPreferencesOrFCMWhileClosed() throws {
        let f = try Fixture()
        XCTAssertNil(f.observe("A"))
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .account("A"))
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        f.delegate.runAccountStartup(authOnly: { f.events.append("auth") }, readerSteps: f.readerSteps(), observeAuth: {})
        XCTAssertEqual(f.publications, 0); XCTAssertTrue(f.effects.isEmpty)
        XCTAssertFalse(f.delegate.readerWorkGuard()())
    }

    func testLegacyLaunchRetainsAuthThenReaderThenObservationOrdering() throws {
        let f = try Fixture(legacy: true)
        f.delegate.runAccountStartup(authOnly: { f.events.append("auth") }, readerSteps: f.readerSteps(), observeAuth: {
            f.events.append("observe"); XCTAssertNotNil(f.observe(nil))
        })
        XCTAssertEqual(f.events, ["auth", "reference", "profile", "favorites", "preferences", "FCM", "observe", "publish:guest"])
        XCTAssertEqual(f.auth.state.snapshot.context, .guest)
        XCTAssertEqual(f.publications, 1)
        XCTAssertTrue(f.effects.values.allSatisfy { $0 == 1 })
    }

    func testLegacyGuestAndAccountPublishImmediatelyButEachReleaseIsConsumed() throws {
        let f = try Fixture(legacy: true)
        XCTAssertNotNil(f.observe(nil)); let guest = f.context
        XCTAssertNil(f.auth.releaseReaderSession(context: guest))
        XCTAssertNotNil(f.observe("A")); let a = f.context
        XCTAssertNil(f.auth.releaseReaderSession(context: a))
        XCTAssertEqual(f.auth.state.snapshot.context, .account("A"))
        XCTAssertEqual(f.events, ["publish:guest", "publish:A"]); XCTAssertEqual(f.publications, 2)
    }

    func testDelayedRealStartupReleasesOnlyOriginalAccountExactlyOnce() async throws {
        let f = try Fixture(); f.observe("A"); let context = f.context
        let gate = Gate(expectation(description: "Original marker is held")); f.markerGate = gate
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertNil(f.auth.releaseReaderSession(context: context))
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
        XCTAssertEqual(f.publications, 0); XCTAssertTrue(f.effects.isEmpty)
        gate.release(); await fulfillment(of: [pending.done], timeout: 3)
        guard case .success(let receipt) = pending.result else { return XCTFail("Expected admitted startup") }
        XCTAssertEqual(receipt.challenge.context, context)
        XCTAssertEqual(f.starts, 1); XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertNotNil(f.auth.releaseReaderSession(context: context))
        XCTAssertNil(f.auth.releaseReaderSession(context: context))
        XCTAssertEqual(f.publications, 1); XCTAssertEqual(f.auth.state.snapshot.context, .account("A"))
        XCTAssertTrue(f.delegate.performReaderWork(f.readerSteps()))
        XCTAssertEqual(f.effects.count, 5); XCTAssertTrue(f.effects.values.allSatisfy { $0 == 1 })
    }

    func testRejectedStaleAuthObservationCannotStealAcceptedPendingBPublication() async throws {
        let f = try Fixture(); f.observe("B"); let accepted = f.context
        let gate = Gate(expectation(description: "Accepted B startup waits for marker")); f.markerGate = gate
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        XCTAssertNil(f.observe("A", updateActual: false), "Delayed A callback no longer matches the provider's B")
        XCTAssertEqual(f.actualUID, "B"); XCTAssertEqual(f.context, accepted)
        XCTAssertEqual(f.publications, 0); XCTAssertNil(f.auth.releaseReaderSession(context: accepted))
        gate.release(); await fulfillment(of: [pending.done], timeout: 3)
        guard case .success(let receipt) = pending.result else { return XCTFail("B startup should remain valid") }
        XCTAssertEqual(receipt.challenge.context, accepted)
        XCTAssertNotNil(f.auth.releaseReaderSession(context: accepted))
        XCTAssertNil(f.auth.releaseReaderSession(context: accepted))
        XCTAssertEqual(f.publications, 1); XCTAssertEqual(f.auth.state.snapshot.context, .account("B"))
        XCTAssertFalse(f.events.contains("publish:A"))
    }

    func testMissingMembershipAndVerifierFailureNeverReleaseReaderState() async throws {
        for missing in [true, false] {
            let f = try Fixture(); f.observe("A")
            f.missingMembership = missing; f.verifierFails = !missing
            let pending = launch(f); await expectFailure(pending)
            XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
            XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
            XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publications, 0); XCTAssertTrue(f.effects.isEmpty)
        }
    }

    func testCancellationBeforeFinalAdmissionNeverPublishesOrStartsSDK() async throws {
        let f = try Fixture(); f.observe("A"); let context = f.context
        let gate = Gate(expectation(description: "Starter waits before admission")); f.beforeAdmissionGate = gate
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        pending.task?.cancel(); await expectFailure(pending, .cancelled)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertNil(f.auth.releaseReaderSession(context: context))
        gate.release(); await waitIdle(f.coordinator)
        XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publications, 0)
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
    }

    func testTimeoutWhileMarkerIsHeldRetainsPhysicalWaitAndBlocksPublication() async throws {
        let f = try Fixture(); f.observe("A")
        let gate = Gate(expectation(description: "Marker physical wait")); f.markerGate = gate
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        try XCTUnwrap(f.deadlines.first)(); await expectFailure(pending, .timedOut)
        XCTAssertTrue(f.coordinator.isBusy); XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
        gate.release(); await waitIdle(f.coordinator)
        XCTAssertEqual(f.sdk.status, .idle); XCTAssertEqual(f.publications, 0); XCTAssertEqual(f.starts, 0)
    }

    func testStartupFailureAfterAdmissionNeverReleasesAnUncertainReader() async throws {
        let f = try Fixture(); f.observe("A"); f.starterFails = true
        let pending = launch(f); await expectFailure(pending)
        XCTAssertEqual(f.sdk.status, .uncertain); XCTAssertEqual(f.starts, 1)
        XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
        XCTAssertEqual(f.publications, 0); XCTAssertTrue(f.effects.isEmpty)
    }

    func testLatePhysicalSDKSuccessAfterTimeoutOrCancellationCannotReleaseReaderServices() async throws {
        for cancel in [false, true] {
            let f = try Fixture(); f.observe("A"); let original = f.context
            let gate = Gate(expectation(description: "SDK admitted, physical completion held")); f.afterAdmissionGate = gate
            let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
            XCTAssertEqual(f.starts, 1)
            if cancel { pending.task?.cancel() } else { try XCTUnwrap(f.deadlines.first)() }
            await expectFailure(pending, cancel ? .cancelled : .timedOut)
            XCTAssertTrue(f.coordinator.isBusy)
            XCTAssertNil(f.auth.releaseReaderSession(context: original))
            gate.release(); await waitIdle(f.coordinator)
            XCTAssertEqual(f.sdk.status, .started, "Record physical SDK success without treating it as accepted startup")
            XCTAssertFalse(f.sdk.permitsReaderServices(identity: f.auth.bootstrapIdentity))
            XCTAssertNil(f.auth.releaseReaderSession(context: original))
            XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
            XCTAssertEqual(f.publications, 0); XCTAssertTrue(f.effects.isEmpty)
        }
    }

    func testAccountRoundTripWhileStartupIsHeldCannotReleaseOldOrNewA() async throws {
        let f = try Fixture(); f.observe("A"); let old = f.context
        let gate = Gate(expectation(description: "Old A marker")); f.markerGate = gate
        let pending = launch(f); await fulfillment(of: [gate.entered], timeout: 3)
        f.observe("B"); f.observe("A"); let fresh = f.context
        XCTAssertNotEqual(old, fresh); await expectFailure(pending, .stale)
        XCTAssertNil(f.auth.releaseReaderSession(context: old)); XCTAssertNil(f.auth.releaseReaderSession(context: fresh))
        gate.release(); await waitIdle(f.coordinator)
        XCTAssertEqual(f.starts, 0); XCTAssertEqual(f.publications, 0)
        _ = try await open(f)
        XCTAssertNil(f.auth.releaseReaderSession(context: old))
        XCTAssertNotNil(f.auth.releaseReaderSession(context: fresh)); XCTAssertEqual(f.publications, 1)
    }

    func testExistingReaderIsRevokedBeforeIncomingIdentityCanWaitForStartup() async throws {
        let f = try Fixture(); f.observe("A"); _ = try await open(f)
        XCTAssertNotNil(f.auth.releaseReaderSession(context: f.context)); let priorReader = f.auth.state.contextTicket()
        var observedPublicContexts: [CanonicalSessionState.Context] = []
        let observer = f.auth.bootstrapIdentity.changes.sink { [unowned f] _ in
            MainActor.assumeIsolated { observedPublicContexts.append(f.auth.state.snapshot.context) }
        }
        XCTAssertNil(f.observe("B"))
        XCTAssertEqual(observedPublicContexts, [.unresolved]); XCTAssertFalse(f.auth.state.isCurrent(priorReader))
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps())); XCTAssertEqual(f.publications, 1)
        withExtendedLifetime(observer) {}
    }

    func testActualUIDReentryCannotResumeOuterObservationAfterNestedB() throws {
        let f = try Fixture(legacy: true)
        f.uidHook = { f.uidHook = nil; f.observe("B") }
        XCTAssertNil(f.observe("A"))
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .account("B"))
        XCTAssertEqual(f.auth.state.snapshot.context, .account("B"))
        XCTAssertEqual(f.events, ["publish:B"])
    }

    func testRevocationRefusalCannotAdoptIncomingIdentityOrPublishItsTail() async throws {
        let f = try Fixture(); f.observe("A"); _ = try await open(f)
        XCTAssertNotNil(f.auth.releaseReaderSession(context: f.context)); let original = f.context
        f.revokeHook = { _ in false }
        XCTAssertNil(f.observe("B"))
        XCTAssertEqual(f.context, original); XCTAssertEqual(f.publications, 1)
        XCTAssertNil(f.auth.releaseReaderSession(context: original))
    }

    func testRevokerReentryRetainsNewestIdentityAndRejectsOldGuard() async throws {
        let f = try Fixture(); f.observe("A"); _ = try await open(f)
        XCTAssertNotNil(f.auth.releaseReaderSession(context: f.context))
        var staleGuard: (() -> Bool)?
        f.revokeHook = { stillCurrent in
            staleGuard = stillCurrent; f.revokeHook = nil
            f.observe("C")
            return stillCurrent()
        }
        XCTAssertNil(f.observe("B"))
        XCTAssertEqual(f.auth.bootstrapIdentity.snapshot.context, .account("C"))
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertEqual(staleGuard?(), false); XCTAssertEqual(f.publications, 1)
    }

    func testPublicationReentryCannotReturnAnOldReaderReceiptOrPublishTwice() throws {
        let f = try Fixture(legacy: true)
        f.publishHook = { f.publishHook = nil; f.observe("B") }
        XCTAssertNil(f.observe("A"))
        XCTAssertEqual(f.auth.state.snapshot.context, .account("B"))
        XCTAssertEqual(f.publications, 2)
        XCTAssertNil(f.auth.releaseReaderSession(context: f.context)); XCTAssertEqual(f.publications, 2)
    }

    func testBootstrapRoundTripDuringFirstProfileRevocationStopsOriginalDependentEffects() async throws {
        let f = try Fixture(); f.observe("A"); let original = f.context; _ = try await open(f)
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        f.usePublicationBridge = true
        f.profileRevocationHook = {
            f.profileRevocationHook = nil; f.observe("B"); f.observe("A")
        }
        XCTAssertNil(f.auth.releaseReaderSession(context: original))
        XCTAssertNotEqual(f.context, original)
        XCTAssertEqual(f.auth.state.snapshot.context, .unresolved)
        XCTAssertEqual(f.effects, ["profileRevocation": 1], "No preference revocation, reader dependency or load from stale A")
        XCTAssertEqual(f.publications, 1, "Nested B/new A have no admitted SDK context, so cannot enter the publisher")
        XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
    }

    func testReleaseGetterReentryAfterAuthorizationCannotBorrowOldAAdmission() async throws {
        let f = try Fixture(); f.observe("A"); let original = f.context; _ = try await open(f)
        f.uidHook = { f.uidHook = nil; f.observe("B"); f.observe("A") }
        XCTAssertNil(f.auth.releaseReaderSession(context: original))
        XCTAssertNotEqual(f.context, original); XCTAssertEqual(f.publications, 0)
        XCTAssertNil(f.auth.releaseReaderSession(context: f.context))
        XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
    }

    func testReaderWorkKeepsOriginalContextAcrossLegacyAccountRoundTrip() throws {
        let f = try Fixture(legacy: true); f.observe("A")
        let allowed = f.delegate.readerWorkGuard()
        let completed = f.delegate.performReaderWork([{
            f.events.append("first"); f.observe("B"); f.observe("A")
        }, { f.events.append("stale-tail") }])
        XCTAssertFalse(completed); XCTAssertFalse(allowed())
        XCTAssertFalse(f.events.contains("stale-tail"))
        XCTAssertTrue(f.delegate.readerWorkGuard()())
    }

    func testReaderWorkRejectsProviderUIDChangeBeforeBootstrapCallback() throws {
        let f = try Fixture(legacy: true); f.observe("A")
        let original = f.context, allowed = f.delegate.readerWorkGuard()
        f.actualUID = "B" // Provider changed; the canonical auth callback has not been delivered yet.
        XCTAssertEqual(f.context, original)
        XCTAssertFalse(allowed()); XCTAssertFalse(f.delegate.performReaderWork(f.readerSteps()))
        XCTAssertTrue(f.effects.isEmpty)
    }

    func testReaderWorkRejectsSameUIDReturnDuringItsInjectedIdentityGetter() throws {
        let f = try Fixture(legacy: true); f.observe("A")
        let original = f.context, allowed = f.delegate.readerWorkGuard()
        f.uidHook = { f.uidHook = nil; f.observe("B"); f.observe("A") }
        XCTAssertFalse(allowed())
        XCTAssertNotEqual(f.context, original); XCTAssertTrue(f.effects.isEmpty)
        XCTAssertTrue(f.delegate.readerWorkGuard()())
    }
}
