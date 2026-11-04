import Foundation
import XCTest
@testable import Apropos

@MainActor
final class ReaderDurableJournalTransitionTests: XCTestCase {
    private typealias Operation = ReaderDurableJournalTransition.Operation
    private typealias Receipt = ReaderDurableJournalTransition.Receipt
    private enum Injected: Error { case failed }
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var failure = false
        private var count = 0
        private var waiting: XCTestExpectation?
        private var barrier: DispatchSemaphore?
        var writes: Int { lock.lock(); defer { lock.unlock() }; return count }
        func fail(_ value: Bool) { lock.lock(); failure = value; lock.unlock() }
        func hold(_ expectation: XCTestExpectation) {
            lock.lock(); waiting = expectation; barrier = DispatchSemaphore(value: 0); lock.unlock()
        }
        func release() { lock.lock(); let held = barrier; lock.unlock(); held?.signal() }
        func replace(_ data: Data, _ url: URL) throws {
            lock.lock(); count += 1; let failed = failure, waiting = waiting, barrier = barrier; lock.unlock()
            waiting?.fulfill()
            if let barrier { guard barrier.wait(timeout: .now() + 5) == .success else { throw Injected.failed } }
            if failed { throw Injected.failed }
            try data.write(to: url, options: .atomic)
        }
    }
    @MainActor private final class Pending {
        let done: XCTestExpectation
        var result: Result<Receipt, Error>?
        var task: Task<Void, Never>?
        init(_ done: XCTestExpectation) { self.done = done }
    }
    @MainActor private final class Fixture {
        let root: URL
        let canonical = CanonicalSessionState()
        let membership: ReaderMembershipAuthority
        let markerProbe = Probe(), targetProbe = Probe()
        let store: ReaderTransitionRecoveryStore
        let recovery: ReaderTransitionRecovery
        let journal: ReaderMutationFileJournal
        var uid: String? = "reader-A"
        var drains: [ReaderWriterDrainCoordinator.Completion] = []
        var drainStarted: XCTestExpectation?
        var deadlines: [@MainActor () -> Void] = []
        var context: CanonicalSessionState.ContextTicket { canonical.contextTicket() }
        var markerRoot: URL { root.appendingPathComponent("recovery") }
        var sourceRoot: URL { root.appendingPathComponent("source") }
        var targetRoot: URL { root.appendingPathComponent("target") }
        lazy var writers = ReaderWriterDrainRuntime(canonical: canonical, actualUID: { [unowned self] in self.uid },
            schedule: { [unowned self] in self.deadlines.append($0); return {} },
            makeDrain: { [unowned self] in .init(wait: { [unowned self] callback in
                self.drains.append(callback)
                let next = self.drainStarted; self.drainStarted = nil; next?.fulfill()
            }) }, legacyAdmission: recovery.admission)
        lazy var source = FavoritesFileJournal(rootDirectory: sourceRoot,
            legacyRead: { _ in nil }, legacyAdmission: recovery.admission)
        lazy var model = ReaderDurableJournalTransition(canonical: canonical, membership: membership,
            recovery: recovery, writers: writers, source: source, journal: journal)
        init(root: URL? = nil) {
            let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("durable-transition-" + UUID().uuidString)
            self.root = root
            membership = ReaderMembershipAuthority(canonical: canonical)
            let markerProbe = markerProbe, targetProbe = targetProbe
            store = ReaderTransitionRecoveryStore(rootDirectory: root.appendingPathComponent("recovery"), replace: {
                try markerProbe.replace($0, $1)
            })
            recovery = ReaderTransitionRecovery(store: store)
            journal = ReaderMutationFileJournal(rootDirectory: root.appendingPathComponent("target"), replace: {
                try targetProbe.replace($0, $1)
            })
            select("reader-A")
        }
        func select(_ value: String?) {
            uid = value
            canonical.adopt(value.map { ReaderAccountSession(uid: $0, email: "fixture@example.invalid", isEmailVerified: true) },
                            forceNewGeneration: true)
        }
        func membershipAt(_ epoch: Int64 = 7) throws -> ReaderMembershipContract.Binding {
            let uid = try XCTUnwrap(context.userID)
            let record = try ReaderMembershipContract.decode(data: JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "ownerUID": uid, "epoch": epoch, "state": "active"
            ]), expectedUID: uid)
            let ticket = try XCTUnwrap(membership.beginRead(for: context))
            XCTAssertTrue(membership.completeRead(ticket, record: record, isFromCache: false, hasPendingWrites: false))
            return record.binding
        }
        func begin() throws -> Operation {
            let binding = try membershipAt()
            return try XCTUnwrap(model.begin(context: context, binding: binding))
        }
    }
    private func launch(_ f: Fixture, _ operation: Operation) -> Pending {
        let pending = Pending(expectation(description: "Preparation physically returns"))
        pending.task = Task { @MainActor in
            do { pending.result = .success(try await f.model.prepare(operation)) }
            catch { pending.result = .failure(error) }
            pending.done.fulfill()
        }
        return pending
    }
    private func awaitDrain(_ f: Fixture, _ operation: Operation) async -> Pending {
        let started = expectation(description: "Fresh physical SDK drain")
        f.drainStarted = started
        let pending = launch(f, operation)
        await fulfillment(of: [started], timeout: 5)
        return pending
    }
    private func finish(_ p: Pending) async throws -> Receipt {
        await fulfillment(of: [p.done], timeout: 5)
        return try XCTUnwrap(p.result).get()
    }
    private func fail(_ p: Pending) async {
        await fulfillment(of: [p.done], timeout: 5)
        guard case .failure = p.result else { return XCTFail("Expected failure") }
    }
    private func readMarker(_ f: Fixture) async throws -> ReaderTransitionRecoveryStore.Marker? {
        try await withCheckedThrowingContinuation { c in f.store.read { c.resume(with: $0) } }
    }
    private func assertClosed(_ f: Fixture) async {
        XCTAssertFalse(f.recovery.legacyWritesPermitted)
        do {
            try await f.writers.performWrite(expectedUserID: f.uid ?? "reader-A", stillCurrent: { true }) { _, complete in
                XCTFail("Recovery must block physical SDK write"); complete(nil)
            }
            XCTFail("Legacy SDK write admitted")
        } catch {}
        let namespace = try! XCTUnwrap(FavoritesContext.confirmed(userID: f.uid ?? "reader-A").namespace)
        let result: Result<FavoritesRecord?, Error> = await withCheckedContinuation { c in
            f.source.storage.read(namespace) { c.resume(returning: $0) }
        }
        guard case .failure = result else { return XCTFail("Legacy read may migrate and must be blocked") }
    }

    func testConstructionUnknownStartupBlocksBothWritersWithoutCreatingFiles() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let binding = try f.membershipAt()
        XCTAssertNil(f.model.begin(context: f.context, binding: binding))
        await assertClosed(f)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
        XCTAssertEqual(f.markerProbe.writes, 0); XCTAssertTrue(f.drains.isEmpty)
    }

    func testMissingStartupReadAllowsLegacyAndExplicitPreMarkerAbort() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        XCTAssertTrue(f.recovery.legacyWritesPermitted)
        let operation = try f.begin()
        XCTAssertTrue(f.model.abort(operation))
        var started = false
        try await f.writers.performWrite(expectedUserID: "reader-A", stillCurrent: { true }) { guardNow, done in
            XCTAssertTrue(guardNow()); started = true; done(nil)
        }
        XCTAssertTrue(started); XCTAssertEqual(f.markerProbe.writes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.path))
    }

    func testMarkerIsVerifiedBeforeDrainAndTargetEffectsAndPersistsOnRestart() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin(), pending = await awaitDrain(f, operation)
        let marker = try await readMarker(f)
        XCTAssertEqual(marker?.binding, operation.binding)
        XCTAssertEqual(f.targetProbe.writes, 0)
        XCTAssertFalse(f.model.abort(operation))
        await assertClosed(f)
        f.drains[0](nil)
        let receipt = try await finish(pending)
        XCTAssertTrue(f.model.isCurrent(receipt))
        let restarted = Fixture(root: f.root)
        await assertClosed(restarted)
        try await restarted.recovery.bootstrap()
        await assertClosed(restarted)
        XCTAssertNil(restarted.model.begin(context: restarted.context, binding: operation.binding), "Disk marker is not server membership")
        let newOperation = try restarted.begin(), resumed = await awaitDrain(restarted, newOperation)
        XCTAssertNil(resumed.result); XCTAssertFalse(restarted.model.isCurrent(receipt))
        restarted.drains[0](nil)
        let newReceipt = try await finish(resumed)
        XCTAssertTrue(restarted.model.isCurrent(newReceipt))
        let retained = try await readMarker(restarted)
        XCTAssertEqual(retained, marker); XCTAssertEqual(restarted.markerProbe.writes, 0)
        XCTAssertEqual(restarted.targetProbe.writes, 0, "Exact preservation must not replace original target")
    }

    func testDifferentAccountAndEpochCannotAdoptPersistedOriginalAfterRestart() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let binding = try f.membershipAt()
        let marker = try await f.recovery.seal(binding: binding)
        let restarted = Fixture(root: f.root)
        try await restarted.recovery.bootstrap()
        restarted.select("reader-B")
        let other = try restarted.membershipAt()
        XCTAssertNil(restarted.model.begin(context: restarted.context, binding: other))
        await assertClosed(restarted)
        restarted.select("reader-A")
        let changed = try restarted.membershipAt(8)
        XCTAssertNil(restarted.model.begin(context: restarted.context, binding: changed))
        let retained = try await readMarker(restarted)
        XCTAssertEqual(retained, marker); XCTAssertTrue(restarted.drains.isEmpty)
    }

    func testMarkerFailureClosesPermanentlyAndRetryUsesSameOriginal() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin()
        f.markerProbe.fail(true)
        await fail(launch(f, operation))
        XCTAssertEqual(f.targetProbe.writes, 0); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertFalse(f.model.abort(operation)); await assertClosed(f)
        do { try await f.recovery.bootstrap(); XCTFail("A missing file after attempted seal must not reopen") } catch {}
        await assertClosed(f)
        f.markerProbe.fail(false)
        let retry = await awaitDrain(f, operation)
        f.drains[0](nil)
        _ = try await finish(retry)
        let marker = try await readMarker(f)
        XCTAssertEqual(marker?.binding, operation.binding)
        XCTAssertFalse(f.model.abort(operation))
    }

    func testCancellationDuringMarkerWriteKeepsSlotAndSkipsTargetUntilExplicitRetry() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin(), started = expectation(description: "Physical marker replacement")
        f.markerProbe.hold(started)
        let pending = launch(f, operation)
        await fulfillment(of: [started], timeout: 5)
        pending.task?.cancel()
        XCTAssertTrue(f.model.isBusy); XCTAssertTrue(f.recovery.isBusy)
        XCTAssertFalse(f.model.abort(operation))
        do { try await f.recovery.bootstrap(); XCTFail("Overlapping startup must be rejected") } catch {}
        await assertClosed(f)
        f.markerProbe.release()
        await fail(pending)
        XCTAssertTrue(f.drains.isEmpty); XCTAssertEqual(f.targetProbe.writes, 0)
        let marker = try await readMarker(f)
        let retry = await awaitDrain(f, operation)
        f.drains[0](nil); _ = try await finish(retry)
        let retained = try await readMarker(f)
        XCTAssertEqual(retained, marker)
    }

    func testAccountSwitchDuringMarkerWriteKeepsOriginalDiskBindingWithoutStartingDrain() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin(), started = expectation(description: "Marker is in flight")
        f.markerProbe.hold(started)
        let pending = launch(f, operation)
        await fulfillment(of: [started], timeout: 5)
        f.select("reader-B")
        XCTAssertFalse(f.model.discardInvalidPreparation(operation))
        f.markerProbe.release(); await fail(pending)
        XCTAssertEqual(f.targetProbe.writes, 0); XCTAssertTrue(f.drains.isEmpty)
        XCTAssertTrue(f.model.discardInvalidPreparation(operation))
        let b = try f.membershipAt()
        XCTAssertNil(f.model.begin(context: f.context, binding: b))
        f.select("reader-A")
        XCTAssertNil(f.model.begin(context: f.context, binding: operation.binding), "A -> B -> A cannot revive authority")
        let fresh = try f.begin(), retry = await awaitDrain(f, fresh)
        f.drains[0](nil); _ = try await finish(retry)
        let retained = try await readMarker(f)
        XCTAssertEqual(retained?.binding, operation.binding)
    }

    func testStaleOperationBeforePrepareCannotCreateMarker() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin()
        f.membership.invalidate()
        await fail(launch(f, operation))
        XCTAssertEqual(f.markerProbe.writes, 0); XCTAssertTrue(f.drains.isEmpty)
    }

    func testTimedOutDrainLeavesDurableGateClosedAndRetryWaitsForPhysicalCallback() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        let operation = try f.begin(), pending = await awaitDrain(f, operation)
        f.deadlines[0](); await fail(pending)
        XCTAssertFalse(f.model.abort(operation)); await assertClosed(f)
        await fail(launch(f, operation))
        XCTAssertEqual(f.drains.count, 1); XCTAssertEqual(f.targetProbe.writes, 0)
        f.drains[0](nil)
        for _ in 0..<100 where !f.writers.isPhysicallyIdle { await Task.yield() }
        XCTAssertTrue(f.writers.isPhysicallyIdle)
        let retry = await awaitDrain(f, operation)
        f.drains[1](nil); _ = try await finish(retry)
    }

    func testReadErrorAndDeletedObservedMarkerNeverReopenCurrentGate() async throws {
        let f = Fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try await f.recovery.bootstrap()
        _ = try await f.recovery.seal(binding: f.membershipAt())
        try FileManager.default.removeItem(at: f.markerRoot)
        do { try await f.recovery.bootstrap(); XCTFail("Observed marker loss is not legacy mode") } catch {}
        await assertClosed(f)
        XCTAssertEqual(f.recovery.status, .unavailable)
    }
}
