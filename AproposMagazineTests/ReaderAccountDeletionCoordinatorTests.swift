import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderAccountDeletionCoordinatorTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private enum TestFailure: Error { case unavailable }

    @MainActor private final class Provider {
        var actions: [Model.ActionTicket] = []
        var pending: [Int: CheckedContinuation<Model.ReauthenticationResult, Error>] = [:]
        func reauthenticate(_ action: Model.ActionTicket) async throws -> Model.ReauthenticationResult {
            let index = actions.count
            actions.append(action)
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func succeed(_ index: Int, action: Model.ActionTicket? = nil, uid: String? = nil,
                     authTimeMs: Int64? = nil, kind: Model.ReauthenticationResult.Kind = .reauthenticated) {
            let original = actions[index]
            pending.removeValue(forKey: index)?.resume(returning: .init(action: action ?? original,
                authenticatedUID: uid ?? original.request.expectedUID,
                authTimeMs: authTimeMs ?? (original.startedAtMs / 1_000) * 1_000, kind: kind))
        }
        func fail(_ index: Int, error: Error = TestFailure.unavailable) {
            pending.removeValue(forKey: index)?.resume(throwing: error)
        }
    }

    @MainActor private final class Transport {
        var requests: [Contract.Request] = []
        var proofs: [Model.ReauthenticationResult] = []
        var pending: [Int: CheckedContinuation<Data, Error>] = [:]
        func send(_ request: Contract.Request, _ proof: Model.ReauthenticationResult) async throws -> Data {
            let index = requests.count
            requests.append(request)
            proofs.append(proof)
            // Deliberately ignore task cancellation: accepted network operations
            // may continue, so the physical slot must remain occupied.
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func succeed(_ index: Int, status: String = "scopedCloudDataRemoved", overrides: [String: Any] = [:]) {
            var response: [String: Any] = ["requestID": requests[index].requestID,
                "scope": Contract.scope, "status": status, "accountDeletionComplete": false,
                "unresolved": Contract.unresolved]
            if status == "scopedCloudDataRemoved" { response["removedFavoriteDocuments"] = 3 }
            if status == "paused" { response["code"] = "reader_boundary_unverified" }
            response.merge(overrides) { _, replacement in replacement }
            pending.removeValue(forKey: index)?.resume(returning: try! JSONSerialization.data(withJSONObject: response))
        }
        func fail(_ index: Int, error: Error = TestFailure.unavailable) {
            pending.removeValue(forKey: index)?.resume(throwing: error)
        }
    }

    @MainActor private final class Scheduler {
        struct Entry {
            let interval: TimeInterval
            let fire: @MainActor () -> Void
            var cancelled = false
        }
        var entries: [Entry] = []
        func schedule(_ interval: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Model.Cancellation {
            let index = entries.count
            entries.append(Entry(interval: interval, fire: fire))
            return { [weak self] in self?.entries[index].cancelled = true }
        }
        func fire(_ index: Int, includingCancelled: Bool = false) {
            guard includingCancelled || !entries[index].cancelled else { return }
            entries[index].fire()
        }
    }

    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState()
        let provider = Provider()
        let transport = Transport()
        let scheduler = Scheduler()
        var epoch: Int64? = 7
        var now: Int64 = 1_800_000_000_123
        var epochReads = 0
        var epochReadHook: ((Int) -> Void)?
        lazy var model = Model(canonical: canonical,
            currentMembershipEpoch: { [weak self] _ in
                guard let self else { return nil }
                self.epochReads += 1
                self.epochReadHook?(self.epochReads)
                return self.epoch
            }, reauthenticate: { [provider] in try await provider.reauthenticate($0) },
            send: { [transport] in try await transport.send($0, $1) },
            nowMilliseconds: { [weak self] in self?.now ?? 0 },
            scheduleTimeout: { [scheduler] in scheduler.schedule($0, $1) })

        init() { select() }
        func select(_ uid: String = "reader-A", forceNewGeneration: Bool = false) {
            _ = canonical.adopt(ReaderAccountSession(uid: uid, email: uid + "@example.invalid", isEmailVerified: true),
                                forceNewGeneration: forceNewGeneration)
        }
        @discardableResult func begin(confirmed: Bool = true) -> Bool {
            model.begin(context: canonical.contextTicket(), membershipEpoch: epoch ?? 7, userConfirmed: confirmed)
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Expected local asynchronous state was not reached", file: file, line: line)
    }
    private func startSending(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async {
        XCTAssertTrue(f.begin(), file: file, line: line)
        await eventually({ f.provider.actions.count == 1 }, file: file, line: line)
        f.provider.succeed(0)
        await eventually({ f.transport.requests.count == 1 }, file: file, line: line)
    }

    func testDefaultConstructionAndCanonicalChangesRemainUnavailableAndInert() async {
        let canonical = CanonicalSessionState(), model = Model(canonical: CanonicalSessionState())
        XCTAssertEqual(model.status, .unavailable)
        _ = canonical.adopt(ReaderAccountSession(uid: "reader-A", email: "a@example.invalid", isEmailVerified: true))
        let unavailable = Model(canonical: canonical)
        XCTAssertFalse(unavailable.begin(context: canonical.contextTicket(), membershipEpoch: 1, userConfirmed: true))
        _ = canonical.adopt(nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(unavailable.status, .unavailable)
        XCTAssertFalse(unavailable.hasPhysicalFlight)
        XCTAssertNil(unavailable.requestID)
        XCTAssertFalse(unavailable.accountDeletionComplete)
        XCTAssertEqual(unavailable.unresolved, Contract.unresolved)
    }

    func testExplicitConfirmationIsRequiredBeforeAnyDependencyStarts() async {
        let f = Fixture()
        XCTAssertFalse(f.begin(confirmed: false))
        XCTAssertFalse(f.model.retry(userConfirmed: false))
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(f.provider.actions.isEmpty)
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertTrue(f.scheduler.entries.isEmpty)
        XCTAssertNil(f.model.requestID)
    }

    func testForeignGuestAndStaleContextsOrMismatchedEpochCannotBegin() {
        let f = Fixture(), other = Fixture()
        XCTAssertFalse(f.model.begin(context: other.canonical.contextTicket(), membershipEpoch: 7, userConfirmed: true))
        XCTAssertFalse(f.model.begin(context: f.canonical.contextTicket(), membershipEpoch: 8, userConfirmed: true))
        XCTAssertFalse(f.model.begin(context: f.canonical.contextTicket(), membershipEpoch: 0, userConfirmed: true))
        let old = f.canonical.contextTicket()
        f.select("reader-B")
        XCTAssertFalse(f.model.begin(context: old, membershipEpoch: 7, userConfirmed: true))
        _ = f.canonical.adopt(nil)
        XCTAssertFalse(f.begin())
        _ = f.canonical.suspend()
        XCTAssertFalse(f.begin())
        XCTAssertTrue(f.provider.actions.isEmpty)
    }

    func testPartialReceiptNeverClaimsAccountDeletionOrMutatesCanonicalSession() async {
        let f = Fixture()
        let snapshot = f.canonical.snapshot
        await startSending(f)
        XCTAssertEqual(f.model.status, .submitting)
        XCTAssertTrue(f.model.isWorking)
        XCTAssertEqual(f.transport.requests[0].expectedUID, "reader-A")
        XCTAssertEqual(f.transport.requests[0].membershipEpoch, 7)
        XCTAssertEqual(f.transport.proofs[0].action.context, f.canonical.contextTicket())
        f.transport.succeed(0)
        await eventually { f.model.status == .scopedCloudDataRemoved }
        XCTAssertEqual(f.model.receipt?.removedFavoriteDocuments, 3)
        XCTAssertFalse(f.model.accountDeletionComplete)
        XCTAssertEqual(f.model.unresolved, Contract.unresolved)
        XCTAssertTrue(f.model.message?.contains("kontosletning er ikke gennemført") == true)
        XCTAssertFalse(f.model.canRetry)
        XCTAssertFalse(f.model.hasPhysicalFlight)
        XCTAssertFalse(f.model.isWorking)
        XCTAssertEqual(f.canonical.snapshot.generation, snapshot.generation)
        XCTAssertEqual(f.canonical.snapshot.session, snapshot.session)
    }

    func testPendingAndPausedRemainPartialAndExposeAllUnresolvedScopes() async {
        for status in ["pending", "paused"] {
            let f = Fixture()
            await startSending(f)
            f.transport.succeed(0, status: status)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, status == "pending" ? .pending : .paused)
            XCTAssertNil(f.model.receipt?.removedFavoriteDocuments)
            XCTAssertEqual(f.model.unresolved, Contract.unresolved)
            XCTAssertFalse(f.model.accountDeletionComplete)
            XCTAssertTrue(f.model.canRetry)
        }
    }

    func testRetryRequiresFreshConfirmationAndReauthenticationButSameRequest() async {
        let f = Fixture()
        await startSending(f)
        let originalRequest = f.transport.requests[0], originalAction = f.provider.actions[0]
        f.transport.succeed(0, status: "pending")
        await eventually { f.model.status == .pending }
        XCTAssertFalse(f.model.retry(userConfirmed: false))
        f.now += 5_000
        XCTAssertTrue(f.model.retry(userConfirmed: true))
        XCTAssertFalse(f.model.retry(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        XCTAssertEqual(f.transport.requests.count, 1)
        XCTAssertNotEqual(f.provider.actions[1].actionID, originalAction.actionID)
        XCTAssertEqual(f.provider.actions[1].request, originalRequest)
        f.provider.succeed(1)
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1], originalRequest)
        f.transport.succeed(1)
        await eventually { f.model.status == .scopedCloudDataRemoved }
    }

    func testReplayedPreviousAttemptProofCannotAuthorizeRetry() async {
        let f = Fixture()
        await startSending(f)
        let old = f.provider.actions[0]
        f.transport.fail(0)
        await eventually { f.model.status == .unavailable }
        XCTAssertTrue(f.model.retry(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        f.provider.succeed(1, action: old)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertEqual(f.transport.requests.count, 1)
    }

    func testRefreshForeignUIDOldAndFutureAuthenticationAreRejectedBeforeSend() async {
        for invalid in ["refresh", "uid", "old", "future"] {
            let f = Fixture()
            XCTAssertTrue(f.begin())
            await eventually { f.provider.actions.count == 1 }
            switch invalid {
            case "refresh": f.provider.succeed(0, kind: .sessionRefresh)
            case "uid": f.provider.succeed(0, uid: "reader-B")
            case "old": f.provider.succeed(0, authTimeMs: f.now - 5_000)
            default: f.provider.succeed(0, authTimeMs: f.now + 1)
            }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable, invalid)
            XCTAssertTrue(f.transport.requests.isEmpty, invalid)
            XCTAssertNil(f.model.receipt)
        }
    }

    func testProofFromAnotherCoordinatorCannotAuthorizeSameOwnerRequest() async {
        let f = Fixture(), other = Fixture()
        XCTAssertTrue(f.begin()); XCTAssertTrue(other.begin())
        await eventually { f.provider.actions.count == 1 && other.provider.actions.count == 1 }
        f.provider.succeed(0, action: other.provider.actions[0])
        other.model.cancel(); other.provider.fail(0)
        await eventually { !f.model.hasPhysicalFlight && !other.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testExpiredReauthenticationAndBackwardClockCannotSend() async {
        for delta in [Int64(300_000), -1] {
            let f = Fixture()
            XCTAssertTrue(f.begin())
            await eventually { f.provider.actions.count == 1 }
            f.now += delta
            f.provider.succeed(0)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable)
            XCTAssertTrue(f.transport.requests.isEmpty)
        }
    }

    func testCanonicalRefreshDoesNotBypassPendingReauthentication() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 1 }
        let refresh = f.canonical.beginRefresh(context: f.canonical.contextTicket())!
        _ = f.canonical.acceptRefresh(f.canonical.snapshot.session!, ticket: refresh)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .reauthenticating)
        XCTAssertTrue(f.transport.requests.isEmpty)
        f.provider.succeed(0)
        await eventually { f.transport.requests.count == 1 }
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
    }

    func testDuplicateBeginWhileReauthOrTransportOccupiedDoesNotStartAnotherAttempt() async {
        let f = Fixture()
        XCTAssertTrue(f.begin()); XCTAssertFalse(f.begin())
        await eventually { f.provider.actions.count == 1 }
        XCTAssertFalse(f.begin())
        f.provider.succeed(0)
        await eventually { f.transport.requests.count == 1 }
        XCTAssertFalse(f.begin())
        XCTAssertEqual(f.provider.actions.count, 1)
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
    }

    func testCancelBeforeTaskStartsPreventsAllProviderAndTransportWork() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        f.model.cancel()
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertTrue(f.provider.actions.isEmpty)
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertNil(f.model.requestID)
    }

    func testCancelDuringReauthenticationHoldsSlotAndDiscardsLateProof() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 1 }
        f.model.cancel()
        XCTAssertTrue(f.model.hasPhysicalFlight)
        XCTAssertFalse(f.begin())
        XCTAssertFalse(f.model.retry(userConfirmed: true))
        f.provider.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertNil(f.model.receipt)
    }

    func testCancelDuringSendHoldsSlotUntilLateSuccessDrainsThenNeedsFreshAction() async {
        let f = Fixture()
        await startSending(f)
        let oldRequest = f.transport.requests[0]
        f.model.cancel()
        XCTAssertFalse(f.model.isWorking)
        XCTAssertTrue(f.model.hasPhysicalFlight)
        XCTAssertFalse(f.begin())
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertNil(f.model.receipt)
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 2 }
        XCTAssertEqual(f.provider.actions[1].request, oldRequest)
        f.provider.fail(1)
        await eventually { !f.model.hasPhysicalFlight }
    }

    func testAccountSwitchAndABAReturnRevokeOriginalTransportDelivery() async {
        for returnToA in [false, true] {
            let f = Fixture()
            await startSending(f)
            _ = f.canonical.adopt(nil)
            f.select(returnToA ? "reader-A" : "reader-B")
            XCTAssertEqual(f.model.status, .cancelled)
            XCTAssertFalse(f.begin())
            f.transport.succeed(0)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertNil(f.model.receipt)
            XCTAssertNil(f.model.requestID)
            XCTAssertFalse(f.model.canRetry)
        }
    }

    func testForcedNewGenerationRevokesSameUIDReauthentication() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 1 }
        f.select(forceNewGeneration: true)
        f.provider.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testMembershipChangeDuringProviderOrTransportRevokesOriginalEpoch() async {
        for duringTransport in [false, true] {
            let f = Fixture()
            if duringTransport { await startSending(f) }
            else { XCTAssertTrue(f.begin()); await eventually { f.provider.actions.count == 1 } }
            f.epoch = 8
            f.model.membershipDidChange()
            XCTAssertEqual(f.model.status, .cancelled)
            if duringTransport { f.transport.succeed(0) } else { f.provider.succeed(0) }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertNil(f.model.receipt)
            XCTAssertFalse(f.model.retry(userConfirmed: true))
            XCTAssertTrue(f.begin())
            await eventually { f.provider.actions.count == 2 }
            XCTAssertEqual(f.provider.actions[1].request.membershipEpoch, 8)
            XCTAssertNotEqual(f.provider.actions[1].request.requestID, f.provider.actions[0].request.requestID)
            f.provider.fail(1)
            await eventually { !f.model.hasPhysicalFlight }
        }
    }

    func testMembershipIsCheckedAfterAwaitEvenWithoutChangeNotification() async {
        let f = Fixture()
        await startSending(f)
        f.epoch = nil
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertNil(f.model.receipt)
        XCTAssertNil(f.model.requestID)
    }

    func testTimeoutDuringReauthKeepsPhysicalSlotUntilOriginalReturns() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 1 }
        XCTAssertEqual(f.scheduler.entries[0].interval, 30)
        let id = f.model.requestID
        f.scheduler.fire(0)
        XCTAssertEqual(f.model.status, .timedOut)
        XCTAssertFalse(f.model.isWorking)
        XCTAssertTrue(f.model.hasPhysicalFlight)
        XCTAssertFalse(f.model.canRetry)
        XCTAssertFalse(f.model.retry(userConfirmed: true))
        f.provider.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertEqual(f.model.status, .timedOut)
        XCTAssertEqual(f.model.requestID, id)
        XCTAssertTrue(f.model.canRetry)
    }

    func testTimeoutDuringSendRejectsLateReceiptAndOldDeadlineCannotExpireRetry() async {
        let f = Fixture()
        await startSending(f)
        let request = f.transport.requests[0]
        f.scheduler.fire(0)
        XCTAssertFalse(f.model.retry(userConfirmed: true))
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .timedOut)
        XCTAssertNil(f.model.receipt)
        XCTAssertTrue(f.model.retry(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        f.scheduler.fire(0, includingCancelled: true)
        XCTAssertEqual(f.model.status, .reauthenticating)
        f.provider.succeed(1)
        await eventually { f.transport.requests.count == 2 }
        XCTAssertEqual(f.transport.requests[1], request)
        f.transport.succeed(1)
        await eventually { f.model.status == .scopedCloudDataRemoved }
        XCTAssertTrue(f.scheduler.entries[1].cancelled)
    }

    func testMalformedForeignAndFullDeletionReceiptsAreNeverAccepted() async {
        for changes in [
            ["requestID": String(repeating: "0", count: 64)],
            ["accountDeletionComplete": true], ["unresolved": []],
            ["status": "complete"], ["scope": "all-account-data"]
        ] as [[String: Any]] {
            let f = Fixture()
            await startSending(f)
            f.transport.succeed(0, overrides: changes)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable)
            XCTAssertNil(f.model.receipt)
            XCTAssertFalse(f.model.accountDeletionComplete)
            XCTAssertEqual(f.model.unresolved, Contract.unresolved)
            XCTAssertTrue(f.model.canRetry)
        }
    }

    func testProviderAndTransportFailuresRemainRetryableWithoutInventedReceipt() async {
        for duringTransport in [false, true] {
            let f = Fixture()
            if duringTransport { await startSending(f); f.transport.fail(0) }
            else {
                XCTAssertTrue(f.begin())
                await eventually { f.provider.actions.count == 1 }
                f.provider.fail(0, error: CancellationError())
            }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable)
            XCTAssertTrue(f.model.canRetry)
            XCTAssertNil(f.model.receipt)
        }
    }

    func testReentrantCancellationDuringBeginPublicationWins() async {
        let f = Fixture()
        var armed = true
        let observation = f.model.objectWillChange.sink {
            if armed { armed = false; f.model.cancel() }
        }
        XCTAssertFalse(f.begin())
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertFalse(f.model.hasPhysicalFlight)
        XCTAssertTrue(f.provider.actions.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testReentrantAccountSwitchDuringReceiptPublicationDiscardsReceipt() async {
        let f = Fixture()
        await startSending(f)
        var armed = true
        let observation = f.model.objectWillChange.sink {
            if armed { armed = false; f.select("reader-B") }
        }
        f.transport.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertNil(f.model.receipt)
        XCTAssertNil(f.model.requestID)
        withExtendedLifetime(observation) {}
    }

    func testReentrantEpochGetterCancellationAtSecondAdmissionPreventsProvider() async {
        let f = Fixture()
        f.epochReadHook = { count in
            if count == 2 { f.epochReadHook = nil; f.model.cancel() }
        }
        XCTAssertFalse(f.begin())
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertTrue(f.provider.actions.isEmpty)
        XCTAssertFalse(f.model.hasPhysicalFlight)
    }

    func testReentrantNewAttemptAtSecondAdmissionCannotBeOverwrittenByOuterBegin() async {
        let f = Fixture()
        var acceptedNested = false
        f.epochReadHook = { count in
            if count == 2 {
                f.epochReadHook = nil
                acceptedNested = f.begin()
            }
        }
        XCTAssertFalse(f.begin())
        XCTAssertTrue(acceptedNested)
        await eventually { f.provider.actions.count == 1 }
        XCTAssertTrue(f.model.hasPhysicalFlight)
        f.provider.fail(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.provider.actions.count, 1)
    }

    func testReentrantEpochGetterCancellationImmediatelyBeforeSendPreventsTransport() async {
        let f = Fixture()
        XCTAssertTrue(f.begin())
        await eventually { f.provider.actions.count == 1 }
        f.epochReadHook = { _ in
            if f.model.status == .submitting {
                f.epochReadHook = nil
                f.model.cancel()
            }
        }
        f.provider.succeed(0)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled)
        XCTAssertTrue(f.transport.requests.isEmpty)
    }

    func testReentrantNewAttemptDuringOldFinishKeepsNewActionAndRejectsOldReceipt() async {
        let f = Fixture()
        await startSending(f)
        var acceptedNested = false
        f.epochReadHook = { _ in
            if !f.model.hasPhysicalFlight && f.model.status == .submitting {
                f.epochReadHook = nil
                acceptedNested = f.begin()
            }
        }
        f.transport.succeed(0)
        await eventually { f.provider.actions.count == 2 }
        XCTAssertTrue(acceptedNested)
        XCTAssertEqual(f.model.status, .reauthenticating)
        XCTAssertNil(f.model.receipt)
        XCTAssertTrue(f.model.hasPhysicalFlight)
        f.provider.fail(1)
        await eventually { !f.model.hasPhysicalFlight }
    }

    func testInvalidClockAndUnboundedDeadlineDoNotStartProvider() {
        let f = Fixture()
        f.now = 0
        XCTAssertFalse(f.begin())
        XCTAssertTrue(f.provider.actions.isEmpty)
        for interval in [0.0, -1, .infinity, 121] {
            let model = Model(canonical: f.canonical, currentMembershipEpoch: { _ in 7 },
                reauthenticate: { _ in XCTFail("Invalid deadline must be inert"); throw TestFailure.unavailable },
                send: { _, _ in XCTFail("Invalid deadline must be inert"); return Data() }, timeoutSeconds: interval)
            XCTAssertEqual(model.status, .unavailable)
            XCTAssertFalse(model.begin(context: f.canonical.contextTicket(), membershipEpoch: 7, userConfirmed: true))
        }
    }
}
