import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderMutationDispatcherTests: XCTestCase {
    private typealias Runner = ReaderMutationDispatcher
    private typealias Request = ReaderMutationContract.Request
    private typealias Record = ReaderMutationJournalRecord
    private enum InjectedFailure: Error { case transport, persistence }

    private final class ReplaceGate: @unchecked Sendable {
        let entered: XCTestExpectation
        private let semaphore = DispatchSemaphore(value: 0)
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func hold() throws {
            entered.fulfill()
            guard semaphore.wait(timeout: .now() + 5) == .success else { throw InjectedFailure.persistence }
        }
        func release() { semaphore.signal() }
    }
    private final class DiskProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var failing = false
        private var gate: ReplaceGate?
        private var count = 0
        var replacements: Int { lock.lock(); defer { lock.unlock() }; return count }
        func fail(_ value: Bool) { lock.lock(); failing = value; lock.unlock() }
        func hold(_ value: ReplaceGate?) { lock.lock(); gate = value; lock.unlock() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); count += 1; let fail = failing, gate = gate; lock.unlock()
            try gate?.hold()
            if fail { throw InjectedFailure.persistence }
            try data.write(to: url, options: .atomic)
        }
    }
    @MainActor private final class BeforeSendGate {
        var waiting: CheckedContinuation<Void, Never>?
        func hold() async { await withCheckedContinuation { waiting = $0 } }
        func release() { let continuation = waiting; waiting = nil; continuation?.resume() }
    }
    @MainActor private final class Pending {
        let done: XCTestExpectation
        var result: Result<Runner.Acknowledgement, Error>?
        var task: Task<Void, Never>?
        init(_ done: XCTestExpectation) { self.done = done }
    }
    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-dispatch-" + UUID().uuidString)
        let canonical = CanonicalSessionState()
        let membership: ReaderMembershipAuthority
        let probe = DiskProbe()
        let journal: ReaderMutationFileJournal
        let store: ReaderMutationDispatchStore
        var schedules = 0
        var deadlines: [@MainActor () -> Void] = []
        var scheduleHook: (() -> Void)?
        var cancelDeadlineHook: (() -> Void)?
        var beforeSend: BeforeSendGate?
        var senderEntered: XCTestExpectation?
        var transportStarted: XCTestExpectation?
        var requests: [Request] = []
        var guards: [Runner.Guard] = []
        var callbacks: [CheckedContinuation<Data, Error>] = []
        lazy var runner = makeRunner()
        init() {
            let probe = probe
            journal = ReaderMutationFileJournal(rootDirectory: root, replace: { try probe.replace($0, $1) })
            store = ReaderMutationDispatchStore(journal: journal)
            membership = ReaderMembershipAuthority(canonical: canonical)
            select("reader-A")
        }
        var context: Runner.Context { canonical.contextTicket() }
        func select(_ uid: String?, force: Bool = false) {
            canonical.adopt(uid.map { ReaderAccountSession(uid: $0, email: $0 + "@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: force)
        }
        func accept(_ epoch: Int64 = 7, frozen: Bool = false) throws {
            let uid = try XCTUnwrap(context.userID)
            var wire: [String: Any] = ["schemaVersion": 1, "ownerUID": uid, "epoch": epoch,
                                       "state": frozen ? "deletion_frozen" : "active"]
            if frozen { wire["deletionRequestID"] = try ReaderAccountDeletionContract.Request(expectedUID: uid, membershipEpoch: epoch).requestID }
            let value = try ReaderMembershipContract.decode(data: JSONSerialization.data(withJSONObject: wire), expectedUID: uid)
            let read = try XCTUnwrap(membership.beginRead(for: context))
            XCTAssertTrue(membership.completeRead(read, record: value, isFromCache: false, hasPendingWrites: false))
        }
        func makeRunner(store other: ReaderMutationDispatchStore? = nil) -> Runner {
            Runner(canonical: canonical, membership: membership, store: other ?? store, send: { [unowned self] request, permitted in
                self.guards.append(permitted)
                let entered = self.senderEntered; self.senderEntered = nil; entered?.fulfill()
                if let gate = self.beforeSend { await gate.hold() }
                guard permitted() else { throw Runner.Failure.stale }
                return try await withCheckedThrowingContinuation { continuation in
                    self.requests.append(request); self.callbacks.append(continuation)
                    let started = self.transportStarted; self.transportStarted = nil; started?.fulfill()
                }
            }, schedule: { [unowned self] action in
                self.schedules += 1; self.deadlines.append(action); self.scheduleHook?()
                return { [unowned self] in self.cancelDeadlineHook?() }
            })
        }
    }
    private func request(owner: String = "reader-A", epoch: Int64 = 7,
                         id: String = UUID().uuidString.lowercased(), target: String = "article-1") throws -> Request {
        try Request(binding: .init(ownerUID: owner, epoch: epoch), mutationID: id, expectedRevision: 4,
                    payload: .favoriteRemove(articleID: target))
    }
    private func receipt(_ request: Request) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "scope": ReaderMutationContract.scope,
            "requestID": request.requestID, "status": "committed", "committedRevision": request.expectedRevision + 1,
            "request": try JSONSerialization.jsonObject(with: ReaderMutationContract.encode(request))], options: [.prettyPrinted, .sortedKeys])
    }
    private func read(_ journal: ReaderMutationFileJournal, owner: String = "reader-A") async throws -> Record? {
        let done = expectation(description: "Fresh durable owner read")
        var result: Result<Record?, Error>?
        journal.read(ownerUID: owner) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        return try XCTUnwrap(result).get()
    }
    private func seed(_ f: Fixture, _ request: Request, acknowledged: Data? = nil) async throws {
        let old = try await read(f.journal, owner: request.expectedUID)
        var record: Record
        if let old { record = old }
        else { record = try Record(ownerUID: request.expectedUID) }
        record = try record.appending(request)
        if let acknowledged { record = try record.acknowledging(requestID: request.requestID, receiptData: acknowledged) }
        let done = expectation(description: "Seed original persisted intent")
        var result: Result<Void, Error>?
        f.journal.write(record, expectedRevision: old?.recordRevision) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        _ = try XCTUnwrap(result).get()
    }
    private func launch(_ f: Fixture, _ request: Request, runner: Runner? = nil,
                        context: Runner.Context? = nil, history: Bool = false) -> Pending {
        let pending = Pending(expectation(description: "Logical dispatch result")), model = runner ?? f.runner
        let original = context ?? f.context
        pending.task = Task { @MainActor in
            do {
                let result: Runner.Acknowledgement
                if history { result = try await model.retryPersistence(request: request) }
                else { result = try await model.dispatch(context: original, request: request) }
                pending.result = .success(result)
            } catch { pending.result = .failure(error) }
            pending.done.fulfill()
        }
        return pending
    }
    private func sending(_ f: Fixture, _ request: Request) async -> Pending {
        let started = expectation(description: "Physical transport started with original request")
        f.transportStarted = started
        let pending = launch(f, request)
        await fulfillment(of: [started], timeout: 5)
        return pending
    }
    private func success(_ pending: Pending) async throws -> Runner.Acknowledgement {
        await fulfillment(of: [pending.done], timeout: 5)
        return try XCTUnwrap(pending.result).get()
    }
    private func failed(_ pending: Pending, _ expected: Runner.Failure? = nil,
                        file: StaticString = #filePath, line: UInt = #line) async {
        await fulfillment(of: [pending.done], timeout: 5)
        guard case .failure(let error) = pending.result else { return XCTFail("Expected failure", file: file, line: line) }
        if let expected { XCTAssertEqual(error as? Runner.Failure, expected, file: file, line: line) }
    }
    private func settled(_ runner: Runner) async {
        let done = expectation(description: "All physical journal/transport callbacks returned")
        Task { @MainActor in
            let limit = Date().addingTimeInterval(5)
            while runner.isBusy, Date() < limit { await Task.yield() }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 6)
        XCTAssertFalse(runner.isBusy)
    }

    func testInertConstructionSuccessAndRestartAlreadyAcknowledgedNeverResends() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        _ = f.runner; XCTAssertEqual(f.schedules, 0); XCTAssertTrue(f.requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
        let original = try request(), data = try receipt(original)
        try await seed(f, original); try f.accept()
        let pending = await sending(f, original)
        f.callbacks[0].resume(returning: data)
        let acknowledged = try await success(pending)
        XCTAssertEqual(acknowledged.receipt.request, original); XCTAssertEqual(acknowledged.receiptData, data)
        let loaded = try await read(f.journal)
        XCTAssertEqual(loaded?.entries[0].receiptData, data)
        let restartedStore = ReaderMutationDispatchStore(journal: ReaderMutationFileJournal(rootDirectory: f.root))
        let restarted = f.makeRunner(store: restartedStore)
        let replay = launch(f, original, runner: restarted)
        let historical = try await success(replay)
        XCTAssertEqual(historical.receiptData, data); XCTAssertEqual(f.requests.count, 1)
        XCTAssertEqual(historical.journalRevision, acknowledged.journalRevision)
        XCTAssertFalse(f.runner.hasPendingHistory); XCTAssertFalse(f.runner.isBusy)
    }

    func testLateReceiptPersistsOriginalAWhileBOrNewAGenerationGetsNoUISuccess() async throws {
        for roundTrip in [false, true] {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let original = try request(), foreign = try request(owner: "reader-B"), data = try receipt(original)
            try await seed(f, original); try await seed(f, foreign); try f.accept()
            let pending = await sending(f, original)
            f.select("reader-B"); if roundTrip { f.select("reader-A"); try f.accept() }
            await failed(pending, .stale)
            XCTAssertTrue(f.runner.isBusy); XCTAssertFalse(f.guards[0]())
            f.callbacks[0].resume(returning: data); await settled(f.runner)
            let loaded = try await read(f.journal), other = try await read(f.journal, owner: "reader-B")
            XCTAssertEqual(loaded?.entries[0].receiptData, data); XCTAssertNil(other?.entries[0].receiptData)
            XCTAssertFalse(f.guards[0]()); XCTAssertEqual(f.requests.count, 1)
        }
    }

    func testTimeoutRetainsSharedReservationUntilLateReceiptIsDurablyAcknowledged() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let pending = await sending(f, original), competitor = f.makeRunner()
        f.deadlines[0](); await failed(pending, .timedOut)
        XCTAssertTrue(f.runner.isBusy); XCTAssertFalse(f.guards[0]())
        await failed(launch(f, original, runner: competitor), .busy)
        f.callbacks[0].resume(returning: try receipt(original)); await settled(f.runner)
        let loaded = try await read(f.journal)
        XCTAssertNotNil(loaded?.entries[0].receiptData); XCTAssertEqual(f.requests.count, 1)
        XCTAssertFalse(f.guards[0]())
    }

    func testCancellationFlagImmediatelyRevokesGuardAndKeepsPhysicalReservation() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let pending = await sending(f, original)
        pending.task?.cancel()
        XCTAssertFalse(f.guards[0](), "Cancellation is marked before its queued MainActor handler")
        await failed(pending, .cancelled)
        await failed(launch(f, original, runner: f.makeRunner()), .busy)
        f.callbacks[0].resume(returning: try receipt(original)); await settled(f.runner)
        let loaded = try await read(f.journal)
        XCTAssertNotNil(loaded?.entries[0].receiptData); XCTAssertFalse(f.runner.hasPendingHistory)
    }

    func testMembershipFreezeBeforePhysicalTransportStopsSendAtFinalAdapterGuard() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let gate = BeforeSendGate(), entered = expectation(description: "Adapter preparation entered")
        f.beforeSend = gate; f.senderEntered = entered
        let pending = launch(f, original)
        await fulfillment(of: [entered], timeout: 5)
        try f.accept(frozen: true); await failed(pending, .stale)
        XCTAssertTrue(f.runner.isBusy); XCTAssertTrue(f.requests.isEmpty)
        gate.release(); await settled(f.runner)
        XCTAssertTrue(f.requests.isEmpty)
        let loaded = try await read(f.journal); XCTAssertNil(loaded?.entries[0].receiptData)
    }

    func testAdmissionRejectsWrongOwnerEpochAndStaleCanonicalContextWithoutTransport() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original)
        await failed(launch(f, original), .unavailable)
        try f.accept()
        await failed(launch(f, try request(epoch: 8)), .unavailable)
        await failed(launch(f, try request(owner: "reader-B")), .unavailable)
        let stale = f.context
        f.select(nil); f.select("reader-A"); try f.accept()
        await failed(launch(f, original, context: stale), .unavailable)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertEqual(f.schedules, 0)
    }

    func testWrongReceiptNeverAcknowledgesAndExplicitRetryUsesUnchangedRequest() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let pending = await sending(f, original)
        f.callbacks[0].resume(returning: try receipt(request(target: "other-article")))
        await failed(pending); await settled(f.runner)
        XCTAssertFalse(f.runner.hasPendingHistory)
        let loaded = try await read(f.journal); XCTAssertNil(loaded?.entries[0].receiptData)
        let retry = await sending(f, original)
        XCTAssertEqual(f.requests.map(\.requestID), [original.requestID, original.requestID])
        f.callbacks[1].resume(returning: try receipt(original)); _ = try await success(retry)
    }

    func testUnknownTransportFailureLeavesOriginalIntentForExplicitIdenticalRetry() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let first = await sending(f, original)
        f.callbacks[0].resume(throwing: InjectedFailure.transport); await failed(first)
        await settled(f.runner); XCTAssertEqual(f.requests.count, 1)
        let loaded = try await read(f.journal); XCTAssertNil(loaded?.entries[0].receiptData)
        let retry = await sending(f, original)
        XCTAssertEqual(try f.requests.map { try ReaderMutationContract.encode($0) },
                       [try ReaderMutationContract.encode(original), try ReaderMutationContract.encode(original)])
        f.callbacks[1].resume(returning: try receipt(original)); _ = try await success(retry)
    }

    func testAcknowledgementFailureKeepsSharedLeaseAndHistoryOnlyRetryWorksUnderAnotherAccount() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(), data = try receipt(original)
        try await seed(f, original); try f.accept(); f.probe.fail(true)
        let first = await sending(f, original)
        f.callbacks[0].resume(returning: data); await failed(first); await settled(f.runner)
        XCTAssertTrue(f.runner.hasPendingHistory)
        await failed(launch(f, original), .pendingHistory)
        await failed(launch(f, original, runner: f.makeRunner()), .busy)
        let altered = try request(id: original.mutationID, target: "changed-payload")
        await failed(launch(f, altered, history: true), .wrongRequest)
        XCTAssertTrue(f.runner.hasPendingHistory)
        f.select("reader-B"); f.probe.fail(false)
        let retry = launch(f, original, history: true), acknowledged = try await success(retry)
        XCTAssertEqual(acknowledged.receipt.request, original); XCTAssertEqual(acknowledged.receiptData, data)
        XCTAssertEqual(f.requests.count, 1); XCTAssertFalse(f.runner.hasPendingHistory)
        XCTAssertEqual(f.context.userID, "reader-B")
        let loaded = try await read(f.journal); XCTAssertEqual(loaded?.entries[0].receiptData, data)
    }

    func testTimeoutDuringPhysicalAcknowledgementCannotReleaseFileOrSharedLease() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let gate = ReplaceGate(expectation(description: "Physical ACK file replacement held"))
        defer { gate.release() }; f.probe.hold(gate)
        let pending = await sending(f, original)
        f.callbacks[0].resume(returning: try receipt(original))
        await fulfillment(of: [gate.entered], timeout: 5)
        f.deadlines[0](); await failed(pending, .timedOut)
        XCTAssertTrue(f.runner.isBusy)
        await failed(launch(f, original, runner: f.makeRunner()), .busy)
        gate.release(); await settled(f.runner)
        let loaded = try await read(f.journal)
        XCTAssertNotNil(loaded?.entries[0].receiptData); XCTAssertFalse(f.runner.hasPendingHistory)
    }

    func testChangedOrMissingDurableRequestIsNeverSentFromCallerMemory() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(); try await seed(f, original); try f.accept()
        let changed = try request(id: original.mutationID, target: "different")
        await failed(launch(f, changed)); await settled(f.runner)
        await failed(launch(f, try request())); await settled(f.runner)
        XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(f.runner.hasPendingHistory)
    }

    func testMembershipFreezeAfterPhysicalSendPreservesReceiptWithoutPublishingSuccess() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(), data = try receipt(original)
        try await seed(f, original); try f.accept()
        let pending = await sending(f, original)
        try f.accept(frozen: true); await failed(pending, .stale)
        XCTAssertFalse(f.guards[0]())
        f.callbacks[0].resume(returning: data); await settled(f.runner)
        let loaded = try await read(f.journal); XCTAssertEqual(loaded?.entries[0].receiptData, data)
        await failed(launch(f, original), .unavailable)
        XCTAssertEqual(f.requests.count, 1)
    }

    func testSynchronousDeadlineAndScheduleAccountReentryNeverStartTransport() async throws {
        for timeout in [false, true] {
            let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let original = try request(); try await seed(f, original); try f.accept()
            f.scheduleHook = { [unowned f] in
                if timeout { f.deadlines.last?() } else { f.select("reader-B") }
            }
            let pending = launch(f, original)
            await failed(pending, timeout ? .timedOut : .stale); await settled(f.runner)
            XCTAssertTrue(f.requests.isEmpty); XCTAssertFalse(f.runner.hasPendingHistory)
            XCTAssertNotNil(f.store.reserve(request: original), "A never-started worker releases its reservation")
        }
    }

    func testDeadlineCleanupReentryRevokesUISuccessButKeepsDurableReceipt() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(), data = try receipt(original)
        try await seed(f, original); try f.accept()
        let pending = await sending(f, original)
        f.cancelDeadlineHook = { [unowned f] in f.cancelDeadlineHook = nil; f.select("reader-B") }
        f.callbacks[0].resume(returning: data); await failed(pending, .stale); await settled(f.runner)
        let loaded = try await read(f.journal); XCTAssertEqual(loaded?.entries[0].receiptData, data)
        XCTAssertFalse(f.runner.hasPendingHistory)
    }

    func testCancelledHistoryRetryStillFinishesOriginalPhysicalAcknowledgementWithoutResend() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try request(), data = try receipt(original)
        try await seed(f, original); try f.accept(); f.probe.fail(true)
        let first = await sending(f, original)
        f.callbacks[0].resume(returning: data); await failed(first); await settled(f.runner)
        f.probe.fail(false); f.select("reader-B")
        let gate = ReplaceGate(expectation(description: "History-only ACK physically held"))
        defer { gate.release() }; f.probe.hold(gate)
        let retry = launch(f, original, history: true)
        await fulfillment(of: [gate.entered], timeout: 5)
        retry.task?.cancel(); await failed(retry, .cancelled)
        XCTAssertTrue(f.runner.isBusy); XCTAssertTrue(f.runner.hasPendingHistory)
        gate.release(); await settled(f.runner)
        let loaded = try await read(f.journal)
        XCTAssertEqual(loaded?.entries[0].receiptData, data)
        XCTAssertEqual(f.requests.count, 1); XCTAssertFalse(f.runner.hasPendingHistory)
    }
}
