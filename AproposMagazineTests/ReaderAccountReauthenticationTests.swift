import XCTest
@testable import Apropos

@MainActor
final class ReaderAccountReauthenticationTests: XCTestCase {
    private typealias Bridge = ReaderAccountReauthentication<String>
    private typealias Deletion = ReaderAccountDeletionCoordinator
    private enum TestFailure: Error { case provider, sdk, token }

    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isHeld: Bool { continuation != nil }
        func hold() async { await withCheckedContinuation { continuation = $0 } }
        func release() { let value = continuation; continuation = nil; value?.resume() }
    }
    private final class User {
        let uid: String
        init(_ uid: String) { self.uid = uid }
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        var user: User? = User("reader-A")
        var now: Int64 = 1_800_000_000_123
        var bridgeNow: Int64?
        var captureReads = 0, identityReads = 0, actualReads = 0, clockReads = 0, tokenCalls = 0
        var captureHook: (() -> Void)?, identityHook: (() -> Void)?, actualHook: (() -> Void)?, clockHook: (() -> Void)?
        var providerGate: Gate?, sdkGate: Gate?, tokenGate: Gate?
        var providerError: Error?, sdkError: Error?, tokenError: Error?
        var authentication: Bridge.Authentication?
        var actions: [Deletion.ActionTicket] = []
        var credentials: [String] = []
        var proofs: [Deletion.ReauthenticationResult] = []
        var errors: [Error] = []
        var sends: [Deletion.ReauthenticationResult] = []

        lazy var operations = AuthOperationCoordinator(canonical: canonical, actualUserID: { [unowned self] in
            actualReads += 1; actualHook?()
            return user?.uid
        })
        lazy var bridge = Bridge(canonical: canonical, operations: operations, captureUser: { [unowned self] in
            captureReads += 1
            let original = user
            captureHook?()
            guard let original else { return nil }
            return Bridge.HeldUser(uid: original.uid, isCurrent: { [unowned self] in
                identityReads += 1
                let current = user === original
                identityHook?()
                return current
            }, reauthenticate: { [unowned self] credential, permitted in
                guard permitted() else { throw CancellationError() }
                credentials.append(credential)
                if let sdkGate { await sdkGate.hold() }
                if let sdkError { throw sdkError }
                guard permitted() else { throw CancellationError() }
                tokenCalls += 1
                if let tokenGate { await tokenGate.hold() }
                if let tokenError { throw tokenError }
                guard permitted() else { throw CancellationError() }
                return authentication ?? Bridge.Authentication(uid: original.uid, authTimeMs: (now / 1_000) * 1_000)
            })
        }, nowMilliseconds: { [unowned self] in
            clockReads += 1; clockHook?()
            return bridgeNow ?? now
        })
        lazy var deletion = Deletion(canonical: canonical, currentMembershipEpoch: { _ in 7 },
            reauthenticate: { [unowned self] action in
                actions.append(action)
                do {
                    let proof = try await bridge.reauthenticate(action: action) { [unowned self] original in
                        guard original == action else { throw TestFailure.provider }
                        if let providerGate = self.providerGate { await providerGate.hold() }
                        if let providerError = self.providerError { throw providerError }
                        return "credential-for-" + original.actionID.uuidString
                    }
                    proofs.append(proof)
                    return proof
                } catch { errors.append(error); throw error }
            }, send: { [unowned self] request, proof in
                sends.append(proof)
                return try JSONSerialization.data(withJSONObject: [
                    "requestID": request.requestID, "scope": ReaderAccountDeletionContract.scope,
                    "status": "pending", "accountDeletionComplete": false,
                    "unresolved": ReaderAccountDeletionContract.unresolved
                ])
            }, nowMilliseconds: { [unowned self] in now }, scheduleTimeout: { _, _ in {} })

        init() { select("reader-A") }
        func select(_ uid: String?, forceNewGeneration: Bool = false) {
            if user?.uid != uid { user = uid.map(User.init) }
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: forceNewGeneration)
        }
        @discardableResult func begin() -> Bool {
            deletion.begin(context: canonical.contextTicket(), membershipEpoch: 7, userConfirmed: true)
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local asynchronous state was not reached", file: file, line: line)
    }
    private func finished(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async {
        await eventually({ !f.deletion.hasPhysicalFlight && (!f.proofs.isEmpty || !f.errors.isEmpty) }, file: file, line: line)
        XCTAssertFalse(f.operations.isBusy, file: file, line: line)
    }
    private func assertCancelled(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(f.errors.last is CancellationError, file: file, line: line)
        XCTAssertTrue(f.proofs.isEmpty, file: file, line: line)
        XCTAssertTrue(f.sends.isEmpty, file: file, line: line)
    }
    private func assertOccupied(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(f.operations.isBusy, file: file, line: line)
        XCTAssertThrowsError(try f.operations.captureReauthentication(context: f.canonical.contextTicket()), file: file, line: line) {
            guard case AuthOperationCoordinator.Failure.busy = $0 else { return XCTFail("Expected occupied slot", file: file, line: line) }
        }
        XCTAssertThrowsError(try f.operations.signOut {}, file: file, line: line)
    }

    func testConstructionIsInert() {
        let f = Fixture()
        _ = f.bridge
        XCTAssertEqual(f.captureReads, 0); XCTAssertEqual(f.actualReads, 0); XCTAssertEqual(f.clockReads, 0)
        XCTAssertTrue(f.actions.isEmpty); XCTAssertTrue(f.credentials.isEmpty); XCTAssertFalse(f.operations.isBusy)
    }

    func testActualReauthenticationReturnsOriginalActionAndSecondRoundedAuthTimeWithoutLoginOrAccountChange() async {
        let f = Fixture(), original = f.canonical.contextTicket()
        XCTAssertTrue(f.begin()); await finished(f)
        XCTAssertEqual(f.captureReads, 1); XCTAssertEqual(f.tokenCalls, 1)
        XCTAssertEqual(f.proofs.count, 1); XCTAssertEqual(f.sends, f.proofs)
        XCTAssertEqual(f.proofs.first?.action, f.actions.first)
        XCTAssertEqual(f.proofs.first?.authenticatedUID, "reader-A")
        XCTAssertEqual(f.proofs.first?.authTimeMs, (f.now / 1_000) * 1_000)
        XCTAssertEqual(f.proofs.first?.kind, .reauthenticated)
        XCTAssertEqual(f.canonical.contextTicket(), original)
        XCTAssertEqual(f.deletion.status, .pending); XCTAssertFalse(f.deletion.accountDeletionComplete)
    }

    func testHeldUserIsCapturedBeforeProviderAndReplacementInstanceWithSameUIDCannotStartSDK() async {
        let f = Fixture(), gate = Gate()
        f.providerGate = gate
        XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
        XCTAssertEqual(f.captureReads, 1); XCTAssertTrue(f.credentials.isEmpty)
        let context = f.canonical.contextTicket()
        f.user = User("reader-A")
        XCTAssertEqual(f.canonical.contextTicket(), context)
        assertOccupied(f); gate.release(); await finished(f)
        assertCancelled(f); XCTAssertTrue(f.credentials.isEmpty)
    }

    func testSameUIDNewGenerationDuringProviderCannotReauthenticate() async {
        let f = Fixture(), gate = Gate()
        f.providerGate = gate
        XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
        f.select("reader-A", forceNewGeneration: true)
        assertOccupied(f); gate.release(); await finished(f)
        assertCancelled(f); XCTAssertTrue(f.credentials.isEmpty)
    }

    func testAccountGuestAccountDuringSDKCannotReadTokenOrAcceptLateProof() async {
        let f = Fixture(), gate = Gate()
        f.sdkGate = gate
        XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
        f.select(nil); f.select("reader-A")
        assertOccupied(f); gate.release(); await finished(f)
        assertCancelled(f); XCTAssertEqual(f.tokenCalls, 0)
    }

    func testCancelledProviderSuccessAndFailureKeepSlotUntilReturnAndNeverStartSDK() async {
        for fails in [false, true] {
            let f = Fixture(), gate = Gate()
            f.providerGate = gate
            if fails { f.providerError = TestFailure.provider }
            XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
            f.deletion.cancel(); assertOccupied(f)
            gate.release(); await finished(f)
            assertCancelled(f); XCTAssertTrue(f.credentials.isEmpty)
            XCTAssertEqual(f.deletion.status, .cancelled)
        }
    }

    func testCancelledSDKSuccessAndFailureDrainBeforeNewExplicitAttempt() async {
        for fails in [false, true] {
            let f = Fixture(), gate = Gate()
            f.sdkGate = gate
            if fails { f.sdkError = TestFailure.sdk }
            XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
            f.deletion.cancel(); assertOccupied(f)
            gate.release(); await finished(f)
            assertCancelled(f); XCTAssertEqual(f.tokenCalls, 0)
            f.sdkGate = nil; f.sdkError = nil
            XCTAssertTrue(f.begin())
            await eventually { f.sends.count == 1 && !f.deletion.hasPhysicalFlight }
            XCTAssertEqual(f.credentials.count, 2); XCTAssertEqual(f.captureReads, 2)
            XCTAssertEqual(f.proofs.first?.action, f.actions.last)
            XCTAssertNotEqual(f.actions.first?.actionID, f.actions.last?.actionID)
        }
    }

    func testTokenAwaitSharesTheOriginalPhysicalSlotAndRejectsCancellationOrIdentityReplacement() async {
        for cancel in [false, true] {
            let f = Fixture(), gate = Gate()
            f.tokenGate = gate
            XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
            if cancel { f.deletion.cancel() } else { f.user = User("reader-A") }
            assertOccupied(f); gate.release(); await finished(f)
            assertCancelled(f); XCTAssertEqual(f.tokenCalls, 1)
        }
    }

    func testCurrentProviderAndSDKFailuresArePreservedAndReleaseTheSlot() async {
        for stage in [0, 1, 2] {
            let f = Fixture()
            if stage == 0 { f.providerError = TestFailure.provider }
            if stage == 1 { f.sdkError = TestFailure.sdk }
            if stage == 2 { f.tokenError = TestFailure.token }
            XCTAssertTrue(f.begin()); await finished(f)
            XCTAssertTrue(f.errors.last is TestFailure)
            XCTAssertTrue(f.proofs.isEmpty); XCTAssertTrue(f.sends.isEmpty)
            XCTAssertEqual(f.deletion.status, .unavailable)
        }
    }

    func testMismatchedUIDOldFutureZeroAndOutOfRangeAuthTimesCannotAuthorizeDeletion() async {
        let start: Int64 = 1_800_000_000_123, rounded: Int64 = 1_800_000_000_000
        for authentication in [
            Bridge.Authentication(uid: "reader-B", authTimeMs: rounded),
            Bridge.Authentication(uid: "reader-A", authTimeMs: rounded - 1),
            Bridge.Authentication(uid: "reader-A", authTimeMs: start + 1),
            Bridge.Authentication(uid: "reader-A", authTimeMs: 0),
            Bridge.Authentication(uid: "reader-A", authTimeMs: Int64.max)
        ] {
            let f = Fixture(); f.authentication = authentication
            XCTAssertTrue(f.begin()); await finished(f)
            XCTAssertEqual(f.errors.last as? Bridge.Failure, .invalidAuthentication)
            XCTAssertTrue(f.proofs.isEmpty); XCTAssertTrue(f.sends.isEmpty)
        }
    }

    func testInvalidActionAgeOrClockRollbackCannotOpenProvider() async {
        for now: Int64 in [0, 1_800_000_000_122, 1_800_000_300_123, Int64.max] {
            let f = Fixture(); f.bridgeNow = now
            XCTAssertTrue(f.begin()); await finished(f)
            XCTAssertEqual(f.errors.last as? Bridge.Failure, .invalidAuthentication)
            XCTAssertTrue(f.credentials.isEmpty); XCTAssertTrue(f.sends.isEmpty)
            XCTAssertEqual(f.tokenCalls, 0)
        }
    }

    func testActionExpiryDuringSDKCannotBeReplacedWithLaterAuthTime() async {
        let f = Fixture(), gate = Gate(); f.sdkGate = gate
        XCTAssertTrue(f.begin()); await eventually { gate.isHeld }
        f.now += 300_000
        gate.release(); await finished(f)
        XCTAssertEqual(f.errors.last as? Bridge.Failure, .invalidAuthentication)
        XCTAssertTrue(f.proofs.isEmpty); XCTAssertTrue(f.sends.isEmpty)
    }

    func testCaptureAndIdentityGettersReenteringAccountGenerationCannotStartProvider() async {
        for duringCapture in [false, true] {
            let f = Fixture()
            let replace = { [unowned f] in
                f.captureHook = nil; f.identityHook = nil
                f.select("reader-A", forceNewGeneration: true)
            }
            if duringCapture { f.captureHook = replace } else { f.identityHook = replace }
            XCTAssertTrue(f.begin()); await finished(f)
            assertCancelled(f); XCTAssertTrue(f.credentials.isEmpty)
        }
    }

    func testActualUIDGetterReplacingTheHeldInstanceIsCaughtBeforeProvider() async {
        let f = Fixture()
        f.actualHook = { [unowned f] in
            if f.captureReads > 0 { f.actualHook = nil; f.user = User("reader-A") }
        }
        XCTAssertTrue(f.begin()); await finished(f)
        assertCancelled(f); XCTAssertTrue(f.credentials.isEmpty)
    }

    func testClockGetterReentryBeforeProviderOrAfterSDKCannotPublishAProof() async {
        for afterSDK in [false, true] {
            let f = Fixture()
            f.clockHook = { [unowned f] in
                if f.clockReads == (afterSDK ? 2 : 1) {
                    f.clockHook = nil; f.select("reader-A", forceNewGeneration: true)
                }
            }
            XCTAssertTrue(f.begin()); await finished(f)
            assertCancelled(f)
            XCTAssertEqual(f.credentials.count, afterSDK ? 1 : 0)
        }
    }

    func testForeignCanonicalActionAndAlreadyCancelledCallerCannotReuseCompletedProof() async {
        let f = Fixture(); XCTAssertTrue(f.begin()); await finished(f)
        guard let action = f.actions.first else { return XCTFail("Expected real coordinator-issued action") }
        let foreign = Fixture()
        do {
            _ = try await foreign.bridge.reauthenticate(action: action) { _ in XCTFail("Foreign action entered provider"); return "wrong" }
            XCTFail("Foreign canonical action was accepted")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(foreign.captureReads, 0)
        let cancelled = Task { @MainActor in
            try await f.bridge.reauthenticate(action: action) { _ in XCTFail("Cancelled action entered provider"); return "wrong" }
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled action was accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(f.captureReads, 1); XCTAssertFalse(f.operations.isBusy)
    }
}
