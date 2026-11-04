import Combine
import XCTest
@testable import Apropos

@MainActor
final class ReaderLedgerDeletionCoordinatorTests: XCTestCase {
    private typealias Model = ReaderAccountDeletionCoordinator
    private typealias Contract = ReaderAccountDeletionContract
    private enum TestFailure: Error { case unavailable }

    @MainActor private final class Provider {
        var actions: [Model.ActionTicket] = []
        var pending: [Int: CheckedContinuation<Model.ReauthenticationResult, Error>] = [:]
        func authenticate(_ action: Model.ActionTicket) async throws -> Model.ReauthenticationResult {
            let index = actions.count; actions.append(action)
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        func succeed(_ index: Int, action: Model.ActionTicket? = nil) {
            let original = actions[index]
            pending.removeValue(forKey: index)?.resume(returning: .init(action: action ?? original,
                authenticatedUID: original.request.expectedUID,
                authTimeMs: (original.startedAtMs / 1_000) * 1_000, kind: .reauthenticated))
        }
        func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: TestFailure.unavailable) }
    }
    @MainActor private final class Transport {
        var parents: [Contract.Request] = []
        var ledgers: [Contract.LedgerRequest] = []
        var parentProofs: [Model.ReauthenticationResult] = []
        var ledgerProofs: [Model.ReauthenticationResult] = []
        var parentPending: [Int: CheckedContinuation<Data, Error>] = [:]
        var ledgerPending: [Int: CheckedContinuation<Data, Error>] = [:]
        func send(_ request: Contract.Request, _ proof: Model.ReauthenticationResult) async throws -> Data {
            let index = parents.count; parents.append(request); parentProofs.append(proof)
            return try await withCheckedThrowingContinuation { parentPending[index] = $0 }
        }
        func sendLedger(_ request: Contract.LedgerRequest, _ proof: Model.ReauthenticationResult) async throws -> Data {
            let index = ledgers.count; ledgers.append(request); ledgerProofs.append(proof)
            // Ignore logical cancellation deliberately: the physical response
            // must return before the coordinator releases this occupied slot.
            return try await withCheckedThrowingContinuation { ledgerPending[index] = $0 }
        }
        func parentSuccess(_ index: Int, status: String = "scopedCloudDataRemoved") {
            var value: [String: Any] = ["requestID": parents[index].requestID, "scope": Contract.scope,
                "status": status, "accountDeletionComplete": false, "unresolved": Contract.unresolved]
            if status == "scopedCloudDataRemoved" { value["removedFavoriteDocuments"] = 3 }
            if status == "paused" { value["code"] = "reader_boundary_unverified" }
            parentPending.removeValue(forKey: index)?.resume(returning: try! JSONSerialization.data(withJSONObject: value))
        }
        func ledgerSuccess(_ index: Int, status: String = "ledgerDataRemoved", overrides: [String: Any] = [:]) {
            var value: [String: Any] = ["requestID": ledgers[index].requestID, "scope": Contract.ledgerScope,
                "status": status, "accountDeletionComplete": false, "unresolved": Contract.ledgerUnresolved]
            if status != "paused" {
                value["parentRequestID"] = ledgers[index].parentRequestID
                value["removedReceiptDocuments"] = status == "ledgerDataRemoved" ? 4 : 0
                value["removedRevisionDocuments"] = status == "ledgerDataRemoved" ? 2 : 0
            } else { value["code"] = "reader_boundary_unverified" }
            value.merge(overrides) { _, replacement in replacement }
            ledgerPending.removeValue(forKey: index)?.resume(returning: try! JSONSerialization.data(withJSONObject: value))
        }
        func failLedger(_ index: Int) { ledgerPending.removeValue(forKey: index)?.resume(throwing: TestFailure.unavailable) }
    }
    @MainActor private final class Scheduler {
        struct Entry { let fire: @MainActor () -> Void; var cancelled = false }
        var entries: [Entry] = []
        func schedule(_ seconds: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Model.Cancellation {
            XCTAssertEqual(seconds, 30)
            let index = entries.count; entries.append(.init(fire: fire))
            return { [weak self] in self?.entries[index].cancelled = true }
        }
        func fire(_ index: Int, includingCancelled: Bool = false) {
            guard includingCancelled || !entries[index].cancelled else { return }
            entries[index].fire()
        }
    }
    @MainActor private final class Fixture {
        let canonical = CanonicalSessionState(), provider = Provider(), transport = Transport(), scheduler = Scheduler()
        let hasLedgerAdapter: Bool
        var epoch: Int64? = 7
        var now: Int64 = 1_800_000_000_123
        var epochReads = 0
        var epochHook: ((Int) -> Void)?
        private var ledgerSender: Model.LedgerSender? {
            guard hasLedgerAdapter else { return nil }
            return { [transport] in try await transport.sendLedger($0, $1) }
        }
        lazy var model = Model(canonical: canonical,
            currentMembershipEpoch: { [weak self] _ in
                guard let self else { return nil }
                self.epochReads += 1; self.epochHook?(self.epochReads)
                return self.epoch
            }, reauthenticate: { [provider] in try await provider.authenticate($0) },
            send: { [transport] in try await transport.send($0, $1) }, sendLedger: ledgerSender,
            nowMilliseconds: { [weak self] in self?.now ?? 0 },
            scheduleTimeout: { [scheduler] in scheduler.schedule($0, $1) })
        init(hasLedgerAdapter: Bool = true) { self.hasLedgerAdapter = hasLedgerAdapter; select() }
        func select(_ uid: String = "reader-A", forceNewGeneration: Bool = false) {
            canonical.adopt(.init(uid: uid, email: uid + "@example.invalid", isEmailVerified: true),
                            forceNewGeneration: forceNewGeneration)
        }
        @discardableResult func beginParent() -> Bool {
            model.begin(context: canonical.contextTicket(), membershipEpoch: epoch ?? 7, userConfirmed: true)
        }
    }
    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected injected asynchronous state was not reached", file: file, line: line)
    }
    private func parentSending(_ f: Fixture) async {
        XCTAssertTrue(f.beginParent())
        await eventually { f.provider.actions.count == 1 }
        f.provider.succeed(0)
        await eventually { f.transport.parents.count == 1 }
    }
    private func parentComplete(_ f: Fixture) async {
        await parentSending(f); f.transport.parentSuccess(0)
        await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
    }
    private func childSending(_ f: Fixture) async {
        XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        f.provider.succeed(1)
        await eventually { f.transport.ledgers.count == 1 }
    }

    func testLedgerCannotStartWithoutAcceptedParentAndExplicitConfirmation() async {
        let f = Fixture()
        XCTAssertFalse(f.model.canBeginLedgerCleanup)
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
        XCTAssertTrue(f.provider.actions.isEmpty); XCTAssertTrue(f.scheduler.entries.isEmpty)
        await parentComplete(f)
        XCTAssertTrue(f.model.canBeginLedgerCleanup)
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: false))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.provider.actions.count, 1); XCTAssertEqual(f.transport.parents.count, 1)
        XCTAssertTrue(f.transport.ledgers.isEmpty); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertEqual(f.model.requestID, f.transport.parents[0].requestID)
    }

    func testNilLedgerAdapterPreservesWorkingV1AndCannotLaunchTheNewPhase() async {
        let f = Fixture(hasLedgerAdapter: false)
        XCTAssertEqual(f.model.status, .idle)
        await parentComplete(f)
        XCTAssertNotNil(f.model.receipt)
        XCTAssertFalse(f.model.canBeginLedgerCleanup)
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
        XCTAssertEqual(f.provider.actions.count, 1); XCTAssertTrue(f.transport.ledgers.isEmpty)
    }

    func testPendingOrPausedParentNeverAuthorizesLedgerCleanup() async {
        for status in ["pending", "paused"] {
            let f = Fixture(); await parentSending(f); f.transport.parentSuccess(0, status: status)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertFalse(f.model.canBeginLedgerCleanup)
            XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
            XCTAssertTrue(f.model.canRetry); XCTAssertTrue(f.transport.ledgers.isEmpty)
            XCTAssertEqual(f.provider.actions.count, 1)
        }
    }

    func testTwoExplicitPhasesRetainParentAndRequireFreshPhaseBoundReauthentication() async {
        let f = Fixture(), context = f.canonical.contextTicket()
        await parentComplete(f)
        let parent = f.model.receipt, originalAction = f.provider.actions[0]
        f.now += 5_000
        await childSending(f)
        let action = f.provider.actions[1], ledger = f.transport.ledgers[0]
        XCTAssertEqual(originalAction.phase, .cloudSlice); XCTAssertNil(originalAction.ledgerRequest)
        XCTAssertEqual(action.phase, .mutationLedger)
        XCTAssertNotEqual(action.actionID, originalAction.actionID)
        XCTAssertEqual(action.request, originalAction.request)
        XCTAssertEqual(action.ledgerRequest, ledger)
        XCTAssertEqual(ledger.parentRequestID, parent?.requestID)
        XCTAssertEqual(ledger.expectedUID, "reader-A"); XCTAssertEqual(ledger.membershipEpoch, 7)
        XCTAssertEqual(f.model.requestID, ledger.requestID)
        XCTAssertNotEqual(f.model.requestID, parent?.requestID)
        XCTAssertEqual(f.model.receipt, parent); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertEqual(f.transport.ledgerProofs[0].action, action)
        f.transport.ledgerSuccess(0)
        await eventually { f.model.status == .ledgerDataRemoved }
        XCTAssertEqual(f.model.receipt, parent)
        XCTAssertEqual(f.model.ledgerReceipt?.removedReceiptDocuments, 4)
        XCTAssertEqual(f.model.ledgerReceipt?.removedRevisionDocuments, 2)
        XCTAssertFalse(f.model.accountDeletionComplete)
        XCTAssertEqual(f.model.unresolved, Contract.ledgerUnresolved)
        XCTAssertFalse(f.model.canRetry); XCTAssertFalse(f.model.canBeginLedgerCleanup)
        XCTAssertEqual(f.canonical.contextTicket(), context)
    }

    func testParentActionProofCannotAuthorizeIdenticalOwnerLedgerPhase() async {
        let f = Fixture(); await parentComplete(f)
        let parent = f.model.receipt, old = f.provider.actions[0]
        XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        f.provider.succeed(1, action: old)
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .unavailable)
        XCTAssertEqual(f.model.receipt, parent); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertTrue(f.transport.ledgers.isEmpty); XCTAssertTrue(f.model.canRetry)
    }

    func testLedgerRetryKeepsOriginalChildRequestButRequiresNewConfirmationAndProof() async {
        let f = Fixture(); await parentComplete(f); let parent = f.model.receipt
        await childSending(f); let ledger = f.transport.ledgers[0], first = f.provider.actions[1]
        f.transport.ledgerSuccess(0, status: "pending")
        await eventually { f.model.status == .pending && !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.receipt, parent)
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
        XCTAssertFalse(f.model.retry(userConfirmed: false))
        f.now += 5_000; XCTAssertTrue(f.model.retry(userConfirmed: true))
        await eventually { f.provider.actions.count == 3 }
        XCTAssertEqual(f.provider.actions[2].phase, .mutationLedger)
        XCTAssertEqual(f.provider.actions[2].ledgerRequest, ledger)
        XCTAssertNotEqual(f.provider.actions[2].actionID, first.actionID)
        f.provider.succeed(2); await eventually { f.transport.ledgers.count == 2 }
        XCTAssertEqual(f.transport.ledgers[1], ledger); XCTAssertEqual(f.transport.parents.count, 1)
        f.transport.ledgerSuccess(1); await eventually { f.model.status == .ledgerDataRemoved }
        XCTAssertEqual(f.model.receipt, parent)
    }

    func testReplayedLedgerAttemptProofCannotAuthorizeItsRetry() async {
        let f = Fixture(); await parentComplete(f); await childSending(f)
        let old = f.provider.actions[1], parent = f.model.receipt
        f.transport.failLedger(0); await eventually { f.model.status == .unavailable }
        XCTAssertTrue(f.model.retry(userConfirmed: true)); await eventually { f.provider.actions.count == 3 }
        f.provider.succeed(2, action: old); await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.transport.ledgers.count, 1); XCTAssertEqual(f.model.receipt, parent)
        XCTAssertNil(f.model.ledgerReceipt); XCTAssertEqual(f.model.status, .unavailable)
    }

    func testProviderAndLedgerTransportFailuresKeepAcceptedParentForExplicitRetry() async {
        for sending in [false, true] {
            let f = Fixture(); await parentComplete(f); let parent = f.model.receipt
            if sending { await childSending(f); f.transport.failLedger(0) }
            else {
                XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
                await eventually { f.provider.actions.count == 2 }; f.provider.fail(1)
            }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable); XCTAssertEqual(f.model.receipt, parent)
            XCTAssertNil(f.model.ledgerReceipt); XCTAssertTrue(f.model.canRetry)
            XCTAssertFalse(f.model.canBeginLedgerCleanup); XCTAssertFalse(f.model.accountDeletionComplete)
        }
    }

    func testTimeoutDuringLedgerReauthenticationRetainsParentAndPhysicalSlotUntilReturn() async {
        let f = Fixture(); await parentComplete(f); let parent = f.model.receipt
        XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
        await eventually { f.provider.actions.count == 2 }
        let child = f.model.requestID
        f.scheduler.fire(1)
        XCTAssertEqual(f.model.status, .timedOut); XCTAssertEqual(f.model.receipt, parent)
        XCTAssertTrue(f.model.hasPhysicalFlight); XCTAssertFalse(f.model.retry(userConfirmed: true))
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true)); XCTAssertFalse(f.beginParent())
        f.provider.succeed(1); await eventually { !f.model.hasPhysicalFlight }
        XCTAssertTrue(f.transport.ledgers.isEmpty); XCTAssertEqual(f.model.requestID, child)
        XCTAssertEqual(f.model.receipt, parent); XCTAssertTrue(f.model.canRetry)
        XCTAssertTrue(f.model.retry(userConfirmed: true)); await eventually { f.provider.actions.count == 3 }
        XCTAssertEqual(f.provider.actions[2].phase, .mutationLedger)
        f.provider.fail(2); await eventually { !f.model.hasPhysicalFlight }
    }

    func testTimeoutDuringLedgerSendDiscardsLateReceiptAndOldDeadlineCannotExpireRetry() async {
        let f = Fixture(); await parentComplete(f); let parent = f.model.receipt
        await childSending(f); let child = f.transport.ledgers[0]
        f.scheduler.fire(1)
        XCTAssertEqual(f.model.receipt, parent); XCTAssertTrue(f.model.hasPhysicalFlight)
        XCTAssertFalse(f.model.retry(userConfirmed: true))
        f.transport.ledgerSuccess(0); await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .timedOut); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertEqual(f.model.receipt, parent)
        XCTAssertTrue(f.model.retry(userConfirmed: true)); await eventually { f.provider.actions.count == 3 }
        f.scheduler.fire(1, includingCancelled: true)
        XCTAssertEqual(f.model.status, .reauthenticating)
        f.provider.succeed(2); await eventually { f.transport.ledgers.count == 2 }
        XCTAssertEqual(f.transport.ledgers[1], child)
        f.transport.ledgerSuccess(1); await eventually { f.model.status == .ledgerDataRemoved }
        XCTAssertEqual(f.model.receipt, parent)
    }

    func testCancellationClearsParentAndLedgerButCannotReleaseAnOccupiedProviderOrTransport() async {
        for sending in [false, true] {
            let f = Fixture(); await parentComplete(f)
            if sending { await childSending(f) }
            else {
                XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
                await eventually { f.provider.actions.count == 2 }
            }
            f.model.cancel()
            XCTAssertTrue(f.model.hasPhysicalFlight); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
            XCTAssertNil(f.model.requestID); XCTAssertFalse(f.beginParent())
            if sending { f.transport.ledgerSuccess(0) } else { f.provider.succeed(1) }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .cancelled); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
            XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true)); XCTAssertFalse(f.model.retry(userConfirmed: true))
        }
    }

    func testAccountABAAndSameUIDGenerationChangesCannotReuseAcceptedParentOrLateChildResponse() async {
        for sending in [false, true] {
            let f = Fixture(); await parentComplete(f)
            if sending { await childSending(f) }
            if sending { f.select("reader-B"); f.select("reader-A") }
            else { f.select(forceNewGeneration: true) }
            XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
            XCTAssertFalse(f.model.canBeginLedgerCleanup)
            XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
            if sending { f.transport.ledgerSuccess(0); await eventually { !f.model.hasPhysicalFlight } }
            XCTAssertNil(f.model.ledgerReceipt); XCTAssertNil(f.model.requestID)
        }
    }

    func testEpochChangeDuringChildAwaitRevokesParentEvenWithoutNotification() async {
        for sending in [false, true] {
            let f = Fixture(); await parentComplete(f)
            if sending { await childSending(f) }
            else {
                XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
                await eventually { f.provider.actions.count == 2 }
            }
            f.epoch = 8
            if sending { f.transport.ledgerSuccess(0) } else { f.provider.succeed(1) }
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .cancelled); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
            XCTAssertFalse(f.model.canBeginLedgerCleanup); XCTAssertFalse(f.model.retry(userConfirmed: true))
        }
    }

    func testExplicitNewCloudSliceAttemptDropsOldParentAndResetsPhase() async {
        let f = Fixture(); await parentComplete(f)
        XCTAssertTrue(f.beginParent()); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
        await eventually { f.provider.actions.count == 2 }
        XCTAssertEqual(f.provider.actions[1].phase, .cloudSlice); XCTAssertNil(f.provider.actions[1].ledgerRequest)
        XCTAssertFalse(f.model.canBeginLedgerCleanup)
        f.provider.fail(1); await eventually { !f.model.hasPhysicalFlight }
    }

    func testMalformedForeignOrFullAccountLedgerReceiptCannotReplaceAcceptedParent() async {
        for override in [["parentRequestID": String(repeating: "0", count: 64)],
            ["scope": Contract.scope], ["accountDeletionComplete": true], ["removedRevisionDocuments": -1]] as [[String: Any]] {
            let f = Fixture(); await parentComplete(f); let parent = f.model.receipt
            await childSending(f); f.transport.ledgerSuccess(0, overrides: override)
            await eventually { !f.model.hasPhysicalFlight }
            XCTAssertEqual(f.model.status, .unavailable); XCTAssertEqual(f.model.receipt, parent)
            XCTAssertNil(f.model.ledgerReceipt); XCTAssertTrue(f.model.canRetry)
            XCTAssertFalse(f.model.accountDeletionComplete)
        }
    }

    func testReentrantCancellationDuringChildBeginPublicationPreventsAnyNewProvider() async {
        let f = Fixture(); await parentComplete(f)
        var armed = true
        let observation = f.model.objectWillChange.sink { if armed { armed = false; f.model.cancel() } }
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
        await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.provider.actions.count, 1); XCTAssertTrue(f.transport.ledgers.isEmpty)
        XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
        withExtendedLifetime(observation) {}
    }

    func testReentrantAccountSwitchDuringChildReceiptPublicationCannotExposeEitherReceipt() async {
        let f = Fixture(); await parentComplete(f); await childSending(f)
        var armed = true
        let observation = f.model.objectWillChange.sink {
            if armed { armed = false; f.select("reader-B"); f.select("reader-A") }
        }
        f.transport.ledgerSuccess(0); await eventually { !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.model.status, .cancelled); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertNil(f.model.requestID); XCTAssertFalse(f.model.canBeginLedgerCleanup)
        withExtendedLifetime(observation) {}
    }

    func testReentrantEpochGetterCannotLendARevokedParentToChildAdmission() async {
        let f = Fixture(); await parentComplete(f)
        f.epochHook = { _ in f.epochHook = nil; f.model.cancel() }
        XCTAssertFalse(f.model.beginLedgerCleanup(userConfirmed: true))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(f.provider.actions.count, 1); XCTAssertTrue(f.transport.ledgers.isEmpty)
        XCTAssertNil(f.model.receipt); XCTAssertFalse(f.model.hasPhysicalFlight)
    }

    func testReentrantEpochGetterImmediatelyBeforeLedgerSendCannotPublishUsingNewContext() async {
        let f = Fixture(); await parentComplete(f)
        XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true)); await eventually { f.provider.actions.count == 2 }
        f.epochHook = { _ in
            if f.model.status == .submitting { f.epochHook = nil; f.select("reader-B"); f.select("reader-A") }
        }
        f.provider.succeed(1); await eventually { !f.model.hasPhysicalFlight }
        XCTAssertTrue(f.transport.ledgers.isEmpty); XCTAssertNil(f.model.receipt); XCTAssertNil(f.model.ledgerReceipt)
        XCTAssertEqual(f.model.status, .cancelled)
    }

    @MainActor private final class BridgeFixture {
        typealias Bridge = ReaderAccountReauthentication<String>
        let canonical = CanonicalSessionState()
        var now: Int64 = 1_800_000_000_123
        var actions: [Model.ActionTicket] = []
        var credentials: [String] = []
        var proofs: [Model.ReauthenticationResult] = []
        var sdkCalls = 0
        lazy var operations = AuthOperationCoordinator(canonical: canonical, actualUserID: { "reader-A" })
        lazy var bridge = Bridge(canonical: canonical, operations: operations, captureUser: { [unowned self] in
            Bridge.HeldUser(uid: "reader-A", isCurrent: { true }, reauthenticate: { [unowned self] credential, permitted in
                guard permitted() else { throw CancellationError() }
                sdkCalls += 1; credentials.append(credential)
                return .init(uid: "reader-A", authTimeMs: (now / 1_000) * 1_000)
            })
        }, nowMilliseconds: { [unowned self] in now })
        lazy var model = Model(canonical: canonical, currentMembershipEpoch: { _ in 7 },
            reauthenticate: { [unowned self] action in
                let proof = try await bridge.reauthenticate(action: action) { [unowned self] original in
                    self.actions.append(original)
                    return "credential-" + original.actionID.uuidString
                }
                proofs.append(proof); return proof
            }, send: { request, _ in
                try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "scope": Contract.scope,
                    "status": "scopedCloudDataRemoved", "accountDeletionComplete": false,
                    "unresolved": Contract.unresolved, "removedFavoriteDocuments": 3])
            }, sendLedger: { request, _ in
                try JSONSerialization.data(withJSONObject: ["requestID": request.requestID, "parentRequestID": request.parentRequestID,
                    "scope": Contract.ledgerScope, "status": "ledgerDataRemoved", "accountDeletionComplete": false,
                    "unresolved": Contract.ledgerUnresolved, "removedReceiptDocuments": 4, "removedRevisionDocuments": 2])
            }, nowMilliseconds: { [unowned self] in now }, scheduleTimeout: { _, _ in {} })
        init() { canonical.adopt(.init(uid: "reader-A", email: "reader@example.invalid", isEmailVerified: true)) }
    }

    func testActualReauthenticationBridgeAcquiresDistinctCredentialAndSDKProofForBothPhases() async {
        let f = BridgeFixture(), context = f.canonical.contextTicket()
        XCTAssertTrue(f.model.begin(context: context, membershipEpoch: 7, userConfirmed: true))
        await eventually { f.model.status == .scopedCloudDataRemoved && !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.actions.count, 1); XCTAssertEqual(f.sdkCalls, 1); XCTAssertFalse(f.operations.isBusy)
        let parent = f.model.receipt
        f.now += 5_000
        XCTAssertTrue(f.model.beginLedgerCleanup(userConfirmed: true))
        await eventually { f.model.status == .ledgerDataRemoved && !f.model.hasPhysicalFlight }
        XCTAssertEqual(f.actions.count, 2); XCTAssertEqual(f.sdkCalls, 2); XCTAssertEqual(f.proofs.count, 2)
        XCTAssertEqual(f.actions[0].phase, .cloudSlice); XCTAssertEqual(f.actions[1].phase, .mutationLedger)
        XCTAssertNotEqual(f.actions[0].actionID, f.actions[1].actionID)
        XCTAssertNotEqual(f.credentials[0], f.credentials[1])
        XCTAssertEqual(f.proofs[1].action, f.actions[1]); XCTAssertEqual(f.proofs[1].kind, .reauthenticated)
        XCTAssertEqual(f.actions[1].ledgerRequest?.parentRequestID, parent?.requestID)
        XCTAssertEqual(f.model.receipt, parent); XCTAssertFalse(f.model.accountDeletionComplete)
        XCTAssertEqual(f.canonical.contextTicket(), context); XCTAssertFalse(f.operations.isBusy)
    }
}
